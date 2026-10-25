extends VBoxContainer
## Presentation over a confirmed native projection. Only the ordinary view's
## issue callback submits commands; this control never changes material state.

var action_button: MenuButton
var _host: WeakRef

func _init() -> void:
	action_button = MenuButton.new()
	action_button.text = "Move materials…  [Ctrl+M]"
	action_button.tooltip_text = "Move carried material. Stand near the selected machine or belt position."
	action_button.get_popup().about_to_popup.connect(_open_menu)
	action_button.get_popup().id_pressed.connect(_choose)
	add_child(action_button)
	visible = false

func configure(host: Object) -> void:
	_host = weakref(host)
	refresh()

func refusal_text(outcome: Dictionary) -> String:
	# Only explain a definitive native refusal. Transport uncertainty and the
	# historical scripted profile keep the view's original feedback.
	if typeof(outcome.get("accepted")) != TYPE_BOOL or outcome.accepted:
		return ""
	var explanations := {
		"occupied_target": "Use the material menu to recover its contents, then dismantle it.",
		"collector_below_source": "Raise the collector above the mineral surface, using a foundation if needed.",
		"source_too_deep": "Lower the collector: the mineral surface is beyond its extraction depth.",
		"invalid_source_surface": "The mineral surface is unavailable. Choose another place on the deposit."}
	var reason: Variant = outcome.get("reason")
	if typeof(reason) != TYPE_STRING or not explanations.has(reason):
		return ""
	var uncertain: Variant = outcome.get("uncertain", false)
	if typeof(uncertain) != TYPE_BOOL or uncertain:
		return ""
	if _host == null or not is_instance_valid(_host.get_ref()):
		return ""
	var host: Object = _host.get_ref()
	if host.get("legacy_fixture") != false:
		return ""
	var snapshot: Variant = host.get("state")
	if not snapshot is Dictionary:
		return ""
	var options: Variant = snapshot.get("options")
	if not options is Dictionary or typeof(options.get("native")) != TYPE_BOOL or not options.native:
		return ""
	return explanations[reason]

func refresh() -> void:
	var context: Dictionary = _context()
	if context.is_empty():
		visible = false
		action_button.disabled = true
		return
	var cargo: Dictionary = context.cargo
	var lots: Array = cargo.work_lots
	var sheets: Array = cargo.get("sheet_items", [])
	var carrying: bool = cargo.raw > 0 or cargo.products > 0 or not lots.is_empty() \
		or (context.kind == "belt_span" and not sheets.is_empty())
	var occupied: bool = _has_contents(context)
	visible = carrying or occupied
	# Keep this inspector addition to one action row, including expanded Details.
	# The exact carried forms remain available without another wrapping label.
	var summary: String = "%s, %s and %s carried." % [
		_count(cargo.raw, "blank", "blanks"), _count(cargo.products, "plate", "plates"),
		_count(lots.size(), "workpiece", "workpieces")]
	if context.kind == "belt_span" and not sheets.is_empty():
		summary += " %s still carried as one broad item." % _count(sheets.size(), "sheet", "sheets")
	action_button.tooltip_text = summary + "\nMove material near the selected machine or belt position."
	action_button.text = ("Move materials…" if occupied and carrying else "Recover contents…" if occupied else "Insert carried material…") + "  [Ctrl+M]"
	action_button.disabled = not context.usable or _offers(context).is_empty()
	# Preserve a displayed menu's original payloads. A later refresh must not
	# silently retarget a queued selection to another workpiece at the same index.

func _count(amount: int, singular: String, plural: String) -> String:
	return "%d %s" % [amount, singular if amount == 1 else plural]

func _quantity(object: Dictionary, key: String) -> int:
	var value: Variant = object.get(key)
	return value if typeof(value) == TYPE_INT and value >= 0 else -1

func _context() -> Dictionary:
	if _host == null or not is_instance_valid(_host.get_ref()):
		return {}
	var host: Object = _host.get_ref()
	if host.get("legacy_fixture") != false:
		return {}
	var snapshot: Variant = host.get("state")
	if not snapshot is Dictionary:
		return {}
	var options: Variant = snapshot.get("options")
	if not options is Dictionary or typeof(options.get("native")) != TYPE_BOOL or not options.native:
		return {}
	var world_context: Variant = snapshot.get("context")
	var actor: Variant = host.get("client")
	var selected: Variant = host.get("selected")
	if typeof(world_context) != TYPE_STRING or world_context.is_empty() or typeof(actor) != TYPE_STRING or actor.is_empty() or typeof(selected) != TYPE_STRING:
		return {}
	var actors: Variant = snapshot.get("actors")
	var all_cargo: Variant = snapshot.get("cargo")
	var entities: Variant = snapshot.get("entities")
	var stock: Variant = snapshot.get("stock")
	if not actors is Dictionary or not all_cargo is Dictionary or not entities is Dictionary or not stock is Dictionary:
		return {}
	var actor_sample: Variant = actors.get(actor)
	var cargo: Variant = all_cargo.get(actor)
	if not actor_sample is Dictionary or not cargo is Dictionary or _quantity(cargo, "raw") < 0 or _quantity(cargo, "products") < 0:
		return {}
	var lots: Variant = cargo.get("work_lots")
	if not lots is Array or lots.size() > 256:
		return {}
	var identities: Dictionary = {}
	for value: Variant in lots:
		if not value is Dictionary:
			return {}
		var id: Variant = value.get("id")
		var remaining: int = _quantity(value, "remaining")
		var cycle: int = _quantity(value, "cycle_ticks")
		if typeof(id) != TYPE_INT or id <= 0 or identities.has(id) or remaining < 0 or cycle < 1 or remaining > cycle or _quantity(value, "recipe_input") < 1:
			return {}
		identities[id] = true
	var sheets: Variant = cargo.get("sheet_items", [])
	if not sheets is Array or sheets.size() > 4096:
		return {}
	for value: Variant in sheets:
		if not value is Dictionary or typeof(value.get("id")) != TYPE_INT \
				or value.id <= 0 or identities.has(value.id) \
				or typeof(value.get("rotation")) != TYPE_INT or value.rotation not in [0, 1, 2, 3]:
			return {}
		identities[value.id] = true
	for key: String in ["collector", "belt", "input", "held", "output"]:
		if _quantity(stock, key) < 0:
			return {}
	var entity: Variant = entities.get(selected)
	var kind: String = ""
	if entity is Dictionary and typeof(entity.get("kind")) == TYPE_STRING:
		kind = entity.kind
	var slots: Array = []
	var belt_carries := false
	var spans: Variant = snapshot.get("belt_spans", {})
	if spans is Dictionary and spans.get(selected) is Dictionary:
		var span_slots: Variant = spans[selected].get("slots")
		if not span_slots is Array or span_slots.size() > 21:
			return {}
		slots = span_slots
		kind = "belt_span"
		var parts: Variant = snapshot.get("transmission_parts", {})
		var first: Variant = parts.get(spans[selected].get("from")) if parts is Dictionary else null
		var last: Variant = parts.get(spans[selected].get("to")) if parts is Dictionary else null
		if first is Dictionary and last is Dictionary and first.get("center") is Array and last.get("center") is Array and first.center.size() == 3 and last.center.size() == 3 and typeof(first.get("axis")) == TYPE_INT:
			belt_carries = first.axis != 1 and (first.center[0] != last.center[0] or first.center[2] != last.center[2])
	var usable: bool = host.get("explanation_open") == false and host.get("startup_save_pending") == false
	if host.has_method("_can_mutate"):
		var permission: Variant = host.call("_can_mutate")
		usable = usable and typeof(permission) == TYPE_BOOL and permission
	usable = usable and typeof(actor_sample.get("ready")) == TYPE_BOOL and actor_sample.ready
	return {"world": world_context, "actor": actor, "target": selected, "kind": kind,
		"cargo": cargo, "stock": stock, "slots": slots, "belt_carries": belt_carries, "usable": usable}

func _has_contents(context: Dictionary) -> bool:
	match context.kind:
		"belt_span":
			for item: Variant in context.slots:
				if item is Dictionary:
					return true
			return false
		"collector": return context.stock.collector > 0
		"belt": return context.stock.belt > 0
		"processor": return context.stock.input > 0 or context.stock.held > 0 or context.stock.output > 0
	return false

func _offers(context: Dictionary) -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	if context.kind == "belt_span":
		for index: int in context.slots.size():
			var item: Variant = context.slots[index]
			if item == null and context.belt_carries:
				for kind: String in ["raw", "product", "work", "sheet"]:
					var ids: Array = [0] if (kind == "raw" and context.cargo.raw > 0) or (kind == "product" and context.cargo.products > 0) else []
					if kind == "work":
						for lot: Dictionary in context.cargo.work_lots:
							ids.append(lot.id)
					elif kind == "sheet":
						for sheet: Dictionary in context.cargo.get("sheet_items", []):
							ids.append(sheet.id)
					for id: int in ids:
						var label: String
						match kind:
							"raw": label = "blank"
							"product": label = "plate"
							"sheet": label = "broad sheet %d" % id
							_: label = "workpiece %d" % id
						offers.append({"text": "Put %s on belt position %d" % [label, index + 1],
							"wire": {"action": "load_belt_slot", "entity": context.target, "slot": index, "item": kind, "work_id": id}})
				continue
			if not item is Dictionary or _quantity(item, "raw") < 0 or _quantity(item, "products") < 0 or not item.get("work_lots") is Array:
				continue
			var label: String = "blank" if item.raw > 0 else "plate" if item.products > 0 else "workpiece"
			offers.append({"text": "Recover %s from belt position %d" % [label, index + 1],
				"wire": {"action": "recover_belt_slot", "entity": context.target, "slot": index, "expected": item.duplicate(true)}})
		return offers
	if not context.kind in ["collector", "belt", "processor"]:
		return offers
	if _has_contents(context):
		offers.append({"text": "Recover this machine's contents", "wire": {"action": "recover", "entity": context.target}})
	if context.cargo.raw > 0:
		offers.append({"text": "Put one carried blank here", "wire": {"action": "insert_raw", "entity": context.target, "amount": 1}})
	if context.kind == "processor":
		var index: int = 0
		for lot: Dictionary in context.cargo.work_lots:
			index += 1
			var phase: String = "ready" if lot.remaining == 0 else "%d ticks remaining" % lot.remaining
			offers.append({"text": "Put workpiece %d here (%s)" % [index, phase],
				"wire": {"action": "insert_work", "entity": context.target, "work_id": lot.id}})
	return offers

func _open_menu() -> void:
	var popup: PopupMenu = action_button.get_popup()
	popup.clear()
	var context: Dictionary = _context()
	if context.is_empty() or not context.usable:
		return
	for offer: Dictionary in _offers(context):
		var index: int = popup.item_count
		popup.add_item(offer.text, index)
		popup.set_item_metadata(index, {"world": context.world, "actor": context.actor,
			"target": context.target, "wire": offer.wire})

func _choose(id: int) -> void:
	if _host == null or not is_instance_valid(_host.get_ref()):
		return
	var popup: PopupMenu = action_button.get_popup()
	var index: int = popup.get_item_index(id)
	if index < 0:
		return
	var chosen: Dictionary = popup.get_item_metadata(index)
	var context: Dictionary = _context()
	if context.is_empty() or not context.usable or chosen.world != context.world or chosen.actor != context.actor or chosen.target != context.target:
		refresh()
		return
	# Check the original payload against current confirmed holdings. In particular,
	# a missing lot must not become another lot, a float or a replacement recipe.
	for offer: Dictionary in _offers(context):
		if offer.wire == chosen.wire:
			var host: Object = _host.get_ref()
			host.call("issue", chosen.wire.duplicate(true))
			return
	refresh()

class LooseMaterialControls:
	extends MenuButton
	## Lists confirmed loose material. The host remains responsible for reach and custody.

	var _host: WeakRef
	var _offers: Array = []
	var _world := ""
	var _actor := ""

	func _init() -> void:
		text = "Handle loose material…  [Ctrl+L]"
		tooltip_text = "Pick up loose material or push one item along a built channel. Stand near its route."
		get_popup().about_to_popup.connect(_open)
		get_popup().id_pressed.connect(_choose)
		visible = false

	func configure(host: Object) -> void:
		_host = weakref(host)
		refresh()

	func _context() -> Dictionary:
		if _host == null or not is_instance_valid(_host.get_ref()):
			return {}
		var host: Object = _host.get_ref()
		var snapshot: Variant = host.get("state")
		if host.get("legacy_fixture") != false or not snapshot is Dictionary:
			return {}
		var options: Variant = snapshot.get("options")
		var drops: Variant = snapshot.get("dropped_material")
		var actor: Variant = host.get("client")
		var actors: Variant = snapshot.get("actors")
		if not options is Dictionary or options.get("native") != true or not drops is Array or not actors is Dictionary or typeof(actor) != TYPE_STRING or typeof(snapshot.get("context")) != TYPE_STRING:
			return {}
		var sample: Variant = actors.get(actor)
		var usable: bool = sample is Dictionary and sample.get("ready") == true and host.get("explanation_open") == false and host.get("startup_save_pending") == false
		if host.has_method("_can_mutate"):
			usable = usable and host.call("_can_mutate") == true
		return {"drops": drops, "world": snapshot.context, "actor": actor, "usable": usable}

	func refresh() -> void:
		var context := _context()
		visible = not context.is_empty() and not context.drops.is_empty()
		disabled = not visible or not context.usable

	func _open() -> void:
		var context := _context()
		_offers.clear()
		get_popup().clear()
		if context.is_empty() or not context.usable:
			return
		_world = context.world
		_actor = context.actor
		for drop: Variant in context.drops:
			if not drop is Dictionary or not drop.get("center") is Array or drop.center.size() != 3 or typeof(drop.get("raw")) != TYPE_INT or drop.raw < 0 or typeof(drop.get("products")) != TYPE_INT or drop.products < 0 or not drop.get("work_lots") is Array or (drop.raw == 0 and drop.products == 0 and drop.work_lots.is_empty() and int(drop.get("offcuts", 0)) == 0 and int(drop.get("sheets", 0)) == 0):
				continue
			var point: Array = drop.center
			if typeof(point[0]) != TYPE_INT or typeof(point[1]) != TYPE_INT or typeof(point[2]) != TYPE_INT:
				continue
			var label := "%d blank(s), %d plate(s), %d workpiece(s)" % [drop.raw, drop.products, drop.work_lots.size()]
			if drop.has("offcuts"):
				label += ", %d offcut(s), %d sheet(s)" % [drop.offcuts, drop.sheets]
			get_popup().add_item("%s at %s" % [label, str(point)], _offers.size())
			var expected: Dictionary = drop.duplicate(true)
			expected.erase("center")
			_offers.append({"drop": drop.duplicate(true), "wire": {
				"action": "pickup_material", "center": point.duplicate(), "expected": expected}})
			var small_form := ""
			if typeof(drop.get("offcuts", 0)) == TYPE_INT and typeof(drop.get("sheets", 0)) == TYPE_INT \
					and drop.work_lots.is_empty() and int(drop.get("sheets", 0)) == 0 \
					and (not drop.has("sheet_items") or (drop.sheet_items is Array and drop.sheet_items.is_empty())):
				if drop.raw == 1 and drop.products == 0 and drop.get("offcuts", 0) == 0:
					small_form = "raw"
				elif drop.raw == 0 and drop.products == 1 and drop.get("offcuts", 0) == 0:
					small_form = "plate"
				elif drop.raw == 0 and drop.products == 0 and drop.get("offcuts", 0) == 1:
					small_form = "offcut"
			if not small_form.is_empty():
				var directions: Array[Dictionary] = []
				if point[0] % 4 == 0 and point[2] % 4 == 0:
					directions = [
						{"name": "east", "dx": 4, "dz": 0},
						{"name": "west", "dx": -4, "dz": 0},
						{"name": "south", "dx": 0, "dz": 4},
						{"name": "north", "dx": 0, "dz": -4}]
				elif point[2] % 4 == 0 and abs(point[0] % 4) % 2 == 1:
					var x_offset: int = (point[0] % 4 + 4) % 4
					directions = [
						{"name": "east", "dx": 4 - x_offset, "dz": 0},
						{"name": "west", "dx": -x_offset, "dz": 0}]
				elif point[0] % 4 == 0 and abs(point[2] % 4) % 2 == 1:
					var z_offset: int = (point[2] % 4 + 4) % 4
					directions = [
						{"name": "south", "dx": 0, "dz": 4 - z_offset},
						{"name": "north", "dx": 0, "dz": -z_offset}]
				for direction: Dictionary in directions:
					var target: Array = [point[0] + direction.dx, point[1], point[2] + direction.dz]
					var material_name: String = {"raw": "blank", "plate": "plate", "offcut": "offcut"}[small_form]
					get_popup().add_item("Push %s %s → %s" % [material_name,
						direction.name, str(target)], _offers.size())
					_offers.append({"drop": drop.duplicate(true), "wire": {
						"action": "push_channel_small", "from": point.duplicate(),
						"to": target, "form": small_form}})
			var sheets: Variant = drop.get("sheet_items")
			if int(drop.get("sheets", 0)) != 1 or not sheets is Array or sheets.size() != 1 \
					or not sheets[0] is Dictionary or typeof(sheets[0].get("id")) != TYPE_INT \
					or sheets[0].id <= 0 or drop.raw != 0 or drop.products != 0 \
					or not drop.work_lots.is_empty() or int(drop.get("offcuts", 0)) != 0:
				continue
			for direction: Dictionary in [
				{"name": "east", "dx": 4, "dz": 0},
				{"name": "west", "dx": -4, "dz": 0},
				{"name": "south", "dx": 0, "dz": 4},
				{"name": "north", "dx": 0, "dz": -4}]:
				var target: Array = [point[0] + direction.dx, point[1], point[2] + direction.dz]
				get_popup().add_item("Push sheet #%d %s → %s" % [sheets[0].id,
					direction.name, str(target)], _offers.size())
				_offers.append({"drop": drop.duplicate(true), "wire": {
					"action": "push_channel_sheet", "from": point.duplicate(),
					"to": target, "sheet_id": sheets[0].id}})

	func _choose(id: int) -> void:
		var context := _context()
		if context.is_empty() or not context.usable or context.world != _world or context.actor != _actor or id < 0 or id >= _offers.size():
			return
		var chosen: Dictionary = _offers[id]
		for drop: Variant in context.drops:
			if drop is Dictionary and drop == chosen.drop:
				_host.get_ref().issue(chosen.wire.duplicate(true))
				return

class WorkbedInventorySlot:
	extends Button
	## A visual material slot. The parent rechecks native projection on every transfer.
	var owner_view: WeakRef
	var source := ""
	var destination := ""

	func _get_drag_data(_position: Vector2) -> Variant:
		if owner_view == null or not is_instance_valid(owner_view.get_ref()):
			return null
		var payload: Dictionary = owner_view.get_ref().inventory_drag(source)
		if payload.is_empty():
			return null
		var preview := TextureRect.new()
		preview.texture = icon
		preview.custom_minimum_size = Vector2(42, 42)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		set_drag_preview(preview)
		return payload

	func _can_drop_data(_position: Vector2, data: Variant) -> bool:
		return owner_view != null and is_instance_valid(owner_view.get_ref()) \
			and owner_view.get_ref().inventory_can_drop(destination, data)

	func _drop_data(_position: Vector2, data: Variant) -> void:
		if _can_drop_data(Vector2.ZERO, data):
			owner_view.get_ref().inventory_drop(destination, data)

class ArrivalAssemblyControls:
	extends PanelContainer
	## Views the native arrival cargo and sends exact component and press commands.
	## No stock, work timer, reach rule or assembly identity is owned here.

	const COMPONENTS := [
		["wooden_frame", "Wooden frame"], ["wooden_shaft", "Wooden shaft"],
		["wooden_cog", "Wooden cog"], ["receiver_tray", "Receiver tray"],
		["tool_mount", "Tool mount"], ["sliding_guide", "Sliding guide"],
		["cutting_edge", "Cutting edge"], ["anvil", "Anvil"],
		["ram_face", "Ram face"], ["copper_shaft", "Copper shaft"],
		["copper_cog", "Copper cog"], ["wooden_workbench", "Wooden workbench"],
		["wooden_slide", "Wooden slide"], ["copper_slide", "Copper slide"],
		["flat_head", "Flat pressing head"], ["hand_crank", "Hand crank"],
		["channel_narrow_x", "Narrow channel · X"],
		["channel_narrow_z", "Narrow channel · Z"],
		["channel_broad_x", "Broad channel · X"],
		["channel_broad_z", "Broad channel · Z"],
	]
	const COLLECTOR_NEXT := {
		"missing_mount": "Fit a tool mount toward the ore deposit.",
		"missing_edge": "Fit a cutting edge beyond the mount.",
		"missing_receiver": "Fit a receiver tray beside the frame.",
		"ambiguous": "Keep one receiver beside this collector.",
	}
	const TURN_REPEAT_SECONDS := 0.33

	var selected_component := "wooden_frame"
	var _host: WeakRef
	var _snapshot := {}
	var _actor := "P"
	var _selected := ""
	var _press := {}
	var _anvil := ""
	var _route_index := 0
	var _slide_port_index := 0
	var _held_work_id := 0
	var _held_work_ids: Array[int] = []
	var _inventory_ready := false
	var _inventory_broad := false
	var _last_anvil := ""
	var reclaim_button: Button
	var reclaim_row: HBoxContainer
	var reclaim_spacer: Control
	var collector_cut_button: Button
	var collector_status: Label
	var press_status: Label
	var feed_heading: Label
	var feed_actions: HBoxContainer
	var output_heading: Label
	var output_actions: HBoxContainer
	var route_choice: OptionButton
	var slide_port_choice: OptionButton
	var held_work_choice: OptionButton
	var feed_button: Button
	var compact_button: Button
	var refeed_work_button: Button
	var turn_button: Button
	var turn_repeat_timer: Timer
	var turn_hold_source := ""
	var pickup_button: Button
	var recover_work_button: Button
	var inventory_section: VBoxContainer
	var inventory_workbed_heading: Label
	var inventory_player_row: HBoxContainer
	var inventory_workbed_row: HBoxContainer
	var inventory_slots := {}
	var inventory_counts := {}
	var sheet_button: MenuButton
	var broad_refeed_button: MenuButton
	var _broad_press := {}
	var _broad_refeed_offers: Array[Dictionary] = []
	var _broad_refeed_actor := ""
	var _broad_refeed_selected := ""
	var _broad_refeed_world := ""
	var _sheet_offers: Array[Dictionary] = []
	var _sheet_menu_actor := ""
	var _sheet_menu_selected := ""
	var _sheet_menu_world := ""
	var shear_button: Button
	var _shear := {}
	var collector_section: VBoxContainer
	var press_section: VBoxContainer

	func _ready() -> void:
		get_window().focus_exited.connect(stop_turn_hold)

	func configure(host) -> void:
		_host = weakref(host)
		name = "ArrivalAssemblyControls"
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 5)
		add_child(column)
		reclaim_row = HBoxContainer.new()
		reclaim_row.alignment = BoxContainer.ALIGNMENT_BEGIN
		column.add_child(reclaim_row)
		reclaim_button = host._button(reclaim_row, "", _reclaim)
		_style_workshop_icon(reclaim_button, "workshop-reclaim")
		reclaim_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		reclaim_row.visible = false
		collector_section = VBoxContainer.new()
		column.add_child(collector_section)
		collector_status = host._label(collector_section, "", 12, Color("bfd1cc"))
		collector_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var collector_actions := HBoxContainer.new()
		collector_actions.alignment = BoxContainer.ALIGNMENT_CENTER
		collector_section.add_child(collector_actions)
		collector_cut_button = host._button(collector_actions, "", _cut_collector)
		_style_workshop_icon(collector_cut_button, "workshop-cut")
		collector_cut_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		press_section = VBoxContainer.new()
		column.add_child(press_section)
		press_status = host._label(press_section, "Select an anvil with E", 13, Color("bfd1cc"))
		press_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var broad_actions := HBoxContainer.new()
		broad_actions.alignment = BoxContainer.ALIGNMENT_CENTER
		press_section.add_child(broad_actions)
		broad_refeed_button = MenuButton.new()
		broad_refeed_button.icon = load("res://opening/assets/build-icons/broad-refeed.svg")
		broad_refeed_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		broad_refeed_button.custom_minimum_size = Vector2(44, 37)
		broad_refeed_button.focus_mode = Control.FOCUS_ALL
		broad_refeed_button.get_popup().about_to_popup.connect(_open_broad_refeed_menu)
		broad_refeed_button.get_popup().id_pressed.connect(_choose_broad_refeed)
		broad_actions.add_child(broad_refeed_button)
		sheet_button = MenuButton.new()
		sheet_button.icon = load("res://opening/assets/build-icons/sheet.svg")
		sheet_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sheet_button.custom_minimum_size = Vector2(44, 37)
		sheet_button.focus_mode = Control.FOCUS_ALL
		sheet_button.get_popup().about_to_popup.connect(_open_sheet_menu)
		sheet_button.get_popup().id_pressed.connect(_choose_sheet)
		broad_actions.add_child(sheet_button)
		shear_button = host._button(broad_actions, "", _stroke_sheet)
		_style_workshop_icon(shear_button, "workshop-cut")
		route_choice = OptionButton.new()
		route_choice.name = "PressRoute"
		route_choice.tooltip_text = "Choose the side for the next blank · G"
		route_choice.accessibility_name = "Press feed direction, shortcut G"
		route_choice.item_selected.connect(func(index: int) -> void: _route_index = index)
		press_section.add_child(route_choice)
		slide_port_choice = OptionButton.new()
		slide_port_choice.name = "SlideCrankPort"
		slide_port_choice.tooltip_text = "Choose a clear side of the slide's built-in input · V"
		slide_port_choice.accessibility_name = "Slide crank input side, shortcut V"
		slide_port_choice.item_selected.connect(func(index: int) -> void: _slide_port_index = index)
		press_section.add_child(slide_port_choice)
		held_work_choice = OptionButton.new()
		held_work_choice.name = "HeldPressWorkChoice"
		held_work_choice.item_selected.connect(func(index: int) -> void:
			if index >= 0 and index < _held_work_ids.size():
				_held_work_id = _held_work_ids[index]
				_refresh_workbed_inventory(_inventory_ready))
		press_section.add_child(held_work_choice)
		inventory_section = VBoxContainer.new()
		inventory_section.name = "WorkbedInventory"
		inventory_section.add_theme_constant_override("separation", 4)
		press_section.add_child(inventory_section)
		var player_heading: Label = host._label(inventory_section, "CARRIED BY YOU  ⇅  WORKBED", 11, Color("f4bf75"))
		player_heading.tooltip_text = "Select a material icon or drag it between the carried and workbed rows."
		inventory_player_row = HBoxContainer.new()
		inventory_player_row.alignment = BoxContainer.ALIGNMENT_CENTER
		inventory_section.add_child(inventory_player_row)
		_add_inventory_slot(inventory_player_row, "player_raw", "workbed", "ore", "Ore blanks")
		_add_inventory_slot(inventory_player_row, "player_work", "workbed", "press-refeed", "Carried work")
		_add_inventory_slot(inventory_player_row, "player_plate", "player", "plate", "Carried plates")
		_add_inventory_slot(inventory_player_row, "player_offcut", "player", "offcut", "Carried offcuts")
		_add_inventory_slot(inventory_player_row, "player_target", "player", "press-pickup", "Drop workbed material here")
		inventory_workbed_heading = host._label(inventory_section, "ON THE WORKBED  →  OUTLET", 11, Color("f4bf75"))
		inventory_workbed_heading.tooltip_text = "The work face and outlet hold material until you pick it up."
		inventory_workbed_row = HBoxContainer.new()
		inventory_workbed_row.alignment = BoxContainer.ALIGNMENT_CENTER
		inventory_section.add_child(inventory_workbed_row)
		_add_inventory_slot(inventory_workbed_row, "workbed_target", "workbed", "press-feed", "Drop carried material here")
		_add_inventory_slot(inventory_workbed_row, "workbed_work", "workbed", "press-recover", "Work face")
		_add_inventory_slot(inventory_workbed_row, "workbed_output", "workbed", "plate", "Outlet")
		feed_heading = host._label(press_section, "FEED & STROKE", 11, Color("f4bf75"))
		feed_actions = HBoxContainer.new()
		feed_actions.alignment = BoxContainer.ALIGNMENT_CENTER
		press_section.add_child(feed_actions)
		feed_button = host._button(feed_actions, "", _feed)
		_style_workshop_icon(feed_button, "press-feed")
		refeed_work_button = host._button(feed_actions, "", _refeed_work)
		_style_workshop_icon(refeed_work_button, "press-refeed")
		turn_button = host._button(feed_actions, "", _turn)
		_style_workshop_icon(turn_button, "press-turn")
		turn_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		turn_button.button_down.connect(_start_turn_hold.bind("pointer"))
		turn_button.button_up.connect(stop_turn_hold.bind("pointer"))
		turn_button.focus_exited.connect(stop_turn_hold)
		turn_repeat_timer = Timer.new()
		turn_repeat_timer.wait_time = TURN_REPEAT_SECONDS
		turn_repeat_timer.one_shot = true
		turn_repeat_timer.timeout.connect(_repeat_turn)
		add_child(turn_repeat_timer)
		compact_button = host._button(feed_actions, "", _compact_offcuts)
		compact_button.icon = load("res://opening/assets/menu-icons/compact-offcuts.svg")
		compact_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		compact_button.custom_minimum_size = Vector2(46, 37)
		compact_button.accessibility_name = "Compact four copper offcuts into one stock blank"
		compact_button.focus_mode = Control.FOCUS_ALL
		var compact_shortcut := Shortcut.new()
		var compact_key := InputEventKey.new()
		compact_key.keycode = KEY_B
		compact_shortcut.events = [compact_key]
		compact_button.shortcut = compact_shortcut
		output_heading = host._label(press_section, "OUTPUT & RECOVERY", 11, Color("f4bf75"))
		output_actions = HBoxContainer.new()
		output_actions.alignment = BoxContainer.ALIGNMENT_CENTER
		press_section.add_child(output_actions)
		pickup_button = host._button(output_actions, "", _pickup_exit)
		_style_workshop_icon(pickup_button, "press-pickup")
		recover_work_button = host._button(output_actions, "", _recover_work)
		_style_workshop_icon(recover_work_button, "press-recover")
		collector_section.visible = false
		press_section.visible = false
		visible = false

	func _add_inventory_slot(row: HBoxContainer, key: String, destination: String,
			icon_name: String, description: String) -> void:
		var cell := VBoxContainer.new()
		cell.custom_minimum_size.x = 60
		row.add_child(cell)
		var button := WorkbedInventorySlot.new()
		button.name = key
		button.owner_view = weakref(self)
		button.source = key
		button.destination = destination
		button.icon = load("res://opening/assets/build-icons/%s.svg" % icon_name)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.custom_minimum_size = Vector2(52, 42)
		button.focus_mode = Control.FOCUS_ALL
		button.tooltip_text = description
		button.accessibility_name = description
		button.pressed.connect(_inventory_activate.bind(key))
		cell.add_child(button)
		var count := Label.new()
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count.add_theme_font_size_override("font_size", 11)
		cell.add_child(count)
		inventory_slots[key] = button
		inventory_counts[key] = count

	func _style_workshop_icon(button: Button, icon_name: String) -> void:
		button.icon = load("res://opening/assets/build-icons/%s.svg" % icon_name)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.custom_minimum_size = Vector2(44, 37)
		button.focus_mode = Control.FOCUS_ALL

	func selected_name() -> String:
		return selected_component

	func select_component_name(component_name: String) -> bool:
		for item in COMPONENTS:
			if item[0] == component_name:
				selected_component = component_name
				var host = _host_view()
				if host != null:
					host._update_cursor()
				return true
		return false

	func press_anvil_for(selected: String) -> String:
		return str(_selected_press(_snapshot, selected).get("anvil", ""))

	func _update_context_size() -> void:
		var scroller := get_parent() as ScrollContainer
		if scroller != null:
			scroller.custom_minimum_size.y = 355 if press_section.visible and inventory_section.visible else \
				280 if press_section.visible and _press.get("status") == "ready" \
				else 80 if press_section.visible else 150 if collector_section.visible else 40

	func open_context() -> void:
		var collector := _selected_collector(_snapshot, _selected)
		collector_section.visible = not collector.is_empty() and _press.get("status") != "ready"
		press_section.visible = not collector_section.visible and not _anvil.is_empty()
		_update_context_size()

	func _bearing(point: Array, center: Array) -> String:
		if point.size() != 3 or center.size() != 3:
			return "unknown"
		if point[0] > center[0]: return "east"
		if point[0] < center[0]: return "west"
		if point[2] > center[2]: return "south"
		return "north"

	func refresh(snapshot: Dictionary, actor: String, selected: String, ready: bool) -> void:
		var changed_target := selected != _selected
		_snapshot = snapshot
		_actor = actor
		_selected = selected
		_inventory_ready = ready
		visible = snapshot.get("options", {}).get("native", false) and snapshot.has("hand_sources")
		if not visible:
			reclaim_row.visible = false
			if reclaim_spacer != null:
				reclaim_spacer.visible = false
			return
		var cargo: Dictionary = snapshot.get("cargo", {}).get(actor, {})
		reclaim_button.visible = snapshot.get("placed_components", {}).has(selected)
		reclaim_row.visible = reclaim_button.visible
		if reclaim_spacer != null:
			reclaim_spacer.visible = reclaim_row.visible
		reclaim_button.disabled = not ready or not reclaim_button.visible
		reclaim_button.tooltip_text = "%s · Delete" % ("Reclaim selected placed part" if ready else "Wait for the character")
		reclaim_button.accessibility_name = "Reclaim selected placed part, shortcut Delete"
		var collector: Dictionary = _selected_collector(snapshot, selected)
		var collector_parts: Dictionary = collector.get("parts", {})
		var receiver: Dictionary = snapshot.get("placed_components", {}).get(collector_parts.get("receiver", ""), {})
		var receiver_center: Array = receiver.get("center", [])
		var receiver_full: bool = not receiver_center.is_empty() and not _drop_at(receiver_center).is_empty()
		collector_status.visible = not collector.is_empty()
		collector_cut_button.visible = collector_status.visible
		if collector_status.visible:
			var collector_state := str(collector.get("status", ""))
			collector_status.text = "Collector receiver holds an ore blank. Pick it up before another cut." if receiver_full else \
				"Collector ready. Turn its mounted input to cut one ore blank." if collector_state == "ready" else \
				"Collector: %s" % COLLECTOR_NEXT.get(collector_state, "Choose a clear ore-deposit frame.")
			if collector_state == "ready":
				collector_status.text += "\n" + _receiver_route_status(snapshot)
			var mount_id: String = str(collector_parts.get("mount", ""))
			var mount: Dictionary = snapshot.get("placed_components", {}).get(mount_id, {})
			var crank_fitted := false
			for item: Dictionary in snapshot.get("crank_items", {}).values():
				if item.get("attached_to", "") == mount_id and item.get("port", []) == mount.get("center", []):
					crank_fitted = true
					break
			collector_cut_button.disabled = not ready or collector_state != "ready" or receiver_full \
				or not crank_fitted or not collector_parts.has("mount")
			var cut_hint := "Cut one ore blank"
			if not ready:
				cut_hint = "Wait for the character"
			elif receiver_full:
				cut_hint = "Clear the receiver"
			elif not crank_fitted:
				cut_hint = "Fit a crafted crank to the collector input"
			elif collector_state != "ready":
				cut_hint = COLLECTOR_NEXT.get(collector_state, "Complete the collector")
			collector_cut_button.tooltip_text = "%s · X" % cut_hint
			collector_cut_button.accessibility_name = "Cut one ore blank at the selected collector, shortcut X"
		_press = _selected_press(snapshot, selected)
		_anvil = str(_press.get("anvil", ""))
		var selected_kind: String = str(snapshot.get("placed_components", {}).get(selected, {}).get("component", ""))
		if _anvil.is_empty() and selected_kind == "anvil":
			_anvil = selected
		_broad_press = _selected_broad_press(snapshot, selected)
		_inventory_broad = not _broad_press.is_empty() and selected_kind == "anvil"
		_broad_refeed_offers = _broad_work_offers(snapshot, actor, selected)
		broad_refeed_button.visible = not _broad_refeed_offers.is_empty()
		broad_refeed_button.disabled = not ready
		broad_refeed_button.tooltip_text = "Reinsert carried broad work into this four-anvil press · N"
		broad_refeed_button.accessibility_name = "Reinsert broad sheet work, shortcut N"
		_sheet_offers = _sheet_stage_offers(snapshot, actor, selected)
		sheet_button.visible = not _sheet_offers.is_empty()
		sheet_button.disabled = not ready
		sheet_button.tooltip_text = "Stage a carried copper sheet on the selected four-anvil area · S"
		sheet_button.accessibility_name = "Stage carried sheet on four anvils, shortcut S"
		_shear = _selected_shear(snapshot, selected)
		shear_button.visible = not _shear.is_empty()
		shear_button.disabled = not ready or _shear.get("status") != "ready"
		shear_button.tooltip_text = ("Cut staged copper sheet (%d/4) · X" % int(_shear.get("strokes", 0)) if _shear.get("status") == "ready" \
			else "Power the sheet-cutting head · X")
		shear_button.accessibility_name = "Cut staged copper sheet, shortcut X"
		if _anvil != _last_anvil:
			_route_index = 0
			_slide_port_index = 0
			_last_anvil = _anvil
		var routes: Array = _press.get("open_feeds", [])
		route_choice.clear()
		var work_center := _work_center()
		for route in routes:
			route_choice.add_item("Feed %s  →  exit %s" % [
				_bearing(route.entry, work_center), _bearing(route.exit, work_center)])
		var selected_exit: Array = _press.get("selected_exit", [])
		var selected_route_available := selected_exit.is_empty()
		if not selected_exit.is_empty():
			for index in routes.size():
				if routes[index].get("exit", []) == selected_exit:
					_route_index = index
					selected_route_available = true
					break
		if routes.size() > 0:
			_route_index = mini(_route_index, routes.size() - 1)
			route_choice.select(_route_index)
		route_choice.disabled = not selected_exit.is_empty()
		var sliding: bool = _press.get("parts", {}).has("slide")
		inventory_section.visible = _inventory_broad or (sliding and not _anvil.is_empty())
		var work_face := "flat head" if sliding else "ram"
		var input_id: String = str(_press.get("parts", {}).get("slide" if sliding else "shaft", ""))
		var rotary_input: Dictionary = snapshot.get("placed_components", {}).get(input_id, {})
		var input_ports: Array = rotary_input.get("input_ports", [])
		var fitted_crank: Dictionary = {}
		for item: Dictionary in snapshot.get("crank_items", {}).values():
			if item.get("attached_to", "") == input_id and input_ports.has(item.get("port", [])):
				fitted_crank = item
				break
		var status := str(_press.get("status", ""))
		_held_work_ids.clear()
		held_work_choice.clear()
		for lot in cargo.get("work_lots", []):
			if lot is Dictionary and int(lot.get("id", 0)) > 0 and lot.get("output_form") != "sheet":
				var work_id := int(lot.id)
				_held_work_ids.append(work_id)
				held_work_choice.add_item("Work #%d · %d ticks remain" % [work_id, int(lot.get("remaining", 0))])
		if not _held_work_ids.has(_held_work_id):
			_held_work_id = _held_work_ids[0] if not _held_work_ids.is_empty() else 0
		if _held_work_id > 0:
			held_work_choice.select(_held_work_ids.find(_held_work_id))
		if status == "ready":
			var work := _work_drop()
			var exit_drop := _exit_drop()
			var advice := "Reinsert carried work or feed a blank." if not _held_work_ids.is_empty() \
				else "Feed one carried ore blank." if int(cargo.get("raw", 0)) > 0 \
				else "Compact four carried copper offcuts here to recover a blank." if int(cargo.get("offcuts", 0)) >= 4 \
				else "Cut ore with the multitool or build a collector."
			if not work.is_empty():
				advice = "Pick up the copper offcut beneath the %s before feeding again." % work_face if int(work.get("offcuts", 0)) > 0 \
					else "Exit holds a plate; pick it up, then turn again." if int(exit_drop.get("products", 0)) > 0 \
					else "Turn the crank to advance retained work."
				var work_lots: Array = work.get("work_lots", [])
				if int(work.get("offcuts", 0)) == 0 and not work_lots.is_empty() and work_lots[0] is Dictionary:
					var cycle: int = int(work_lots[0].get("cycle_ticks", 0))
					var remaining: int = int(work_lots[0].get("remaining", 0))
					if cycle > 0 and remaining > 0 and remaining <= cycle:
						if exit_drop.is_empty():
							advice = "Work stroke: %d / %d contacts. Hold T or the turn icon." % [cycle - remaining, cycle] if sliding else \
								"Work stroke: %d / %d steps. Hold T or the turn icon." % [cycle - remaining, cycle]
						else:
							advice = "Exit holds a plate; stroke %d / %d steps. Pick it up before the final step." % [cycle - remaining, cycle]
			if sliding and work.is_empty():
				advice = "Move selected carried work onto the workbed." if not _held_work_ids.is_empty() else \
					"Move one carried blank onto the workbed." if int(cargo.get("raw", 0)) > 0 else \
					"Cut ore with the multitool, then carry a blank here."
			press_status.text = "Selected outlet blocked. Clear it before the next stroke." if not selected_route_available else \
				"%s ready · %d clear feed routes. %s" % [
					"Slide press" if sliding else "Press", routes.size(), advice]
		else:
			press_status.text = "No clear through-feed route. Close [Esc], press F, then click the blocking part." if status == "blocked_feed" else {
				"anvil": "Anvil · work support",
				"ram_face": "Ram face · contact tool",
				"sliding_guide": "Guide · guided motion",
			}.get(selected_kind, "Placed part")
		if _inventory_broad:
			var broad_work: Dictionary = _drop_at(_broad_press.get("origin", []))
			press_status.text = "Four-anvil workbed · sheet ready on supports. Collect [P]." \
				if int(broad_work.get("sheets", 0)) > 0 else \
				"Four-anvil workbed · sheet work retained. Drive or recover it." \
				if not broad_work.get("work_lots", []).is_empty() else \
				"Four-anvil workbed · move three carried blanks here [F]."
		var active_press := status == "ready"
		feed_heading.visible = active_press and not _inventory_broad
		feed_heading.text = "TURN THE SLIDE" if sliding else "FEED & STROKE"
		feed_actions.visible = active_press and not _inventory_broad
		output_heading.visible = active_press and not sliding and not _inventory_broad
		output_heading.text = "CRANK CUSTODY" if sliding else "OUTPUT & RECOVERY"
		output_actions.visible = output_heading.visible
		route_choice.visible = active_press and not _inventory_broad and not routes.is_empty() and (not sliding or routes.size() > 1)
		slide_port_choice.visible = false
		var can_operate := ready and status == "ready" and not routes.is_empty() \
			and selected_route_available
		feed_button.visible = not _inventory_broad and not _anvil.is_empty() and not sliding
		feed_button.disabled = not can_operate or int(cargo.get("raw", 0)) < 1 or not _work_drop().is_empty()
		var operate_cause := "Wait for the character" if not ready else \
			"Clear the selected outlet" if not selected_route_available else \
			"Complete the press and choose a clear feed route"
		feed_button.tooltip_text = "%s · F" % (operate_cause if not can_operate else \
			"Carry an ore blank" if int(cargo.get("raw", 0)) < 1 else \
			"Clear the work face beneath the %s" % work_face if not _work_drop().is_empty() else \
			"Feed one carried ore blank")
		feed_button.accessibility_name = "Feed one carried ore blank, shortcut F"
		compact_button.visible = not sliding and not _anvil.is_empty() and int(cargo.get("offcuts", 0)) > 0
		compact_button.disabled = not can_operate or int(cargo.get("offcuts", 0)) < 4 \
			or fitted_crank.is_empty() or not _work_drop().is_empty() \
			or not _press.get("parts", {}).has("shaft")
		compact_button.tooltip_text = "Compact four carried copper offcuts into one stock blank at this press. Fit a crank and clear the work face. [%d/4]  B" % mini(4, int(cargo.get("offcuts", 0)))
		compact_button.accessibility_name = "Compact four carried copper offcuts into one blank, shortcut B"
		held_work_choice.visible = active_press and not _held_work_ids.is_empty() \
			and (not sliding or _held_work_ids.size() > 1)
		refeed_work_button.visible = active_press and not _held_work_ids.is_empty() and not sliding
		refeed_work_button.disabled = not can_operate or not _work_drop().is_empty()
		refeed_work_button.tooltip_text = "%s · R" % (operate_cause if not can_operate else \
			"Clear the work face beneath the %s" % work_face if not _work_drop().is_empty() else \
			"Reinsert the selected held work")
		refeed_work_button.accessibility_name = "Reinsert selected held work, shortcut R"
		turn_button.visible = not _anvil.is_empty()
		turn_button.disabled = not can_operate or fitted_crank.is_empty() \
			or _work_drop().is_empty() \
			or int(_work_drop().get("offcuts", 0)) > 0
		if changed_target or turn_button.disabled or not turn_button.visible:
			stop_turn_hold()
		turn_button.tooltip_text = "Fit a crafted crank on the input · T" if fitted_crank.is_empty() else "%s · T" % (operate_cause if not can_operate else \
			"Feed or reinsert work beneath the %s" % work_face if _work_drop().is_empty() else \
			"Pick up the copper offcut beneath the %s" % work_face if int(_work_drop().get("offcuts", 0)) > 0 else \
			"Exit holds a plate; turn until blocked, then pick it up" if not _exit_drop().is_empty() else \
			"Hold T or the icon to turn the crank; release to stop")
		turn_button.accessibility_name = "Fit a crafted crank to the input before turning" if fitted_crank.is_empty() else \
			"Hold to turn the slide crank, shortcut T" if sliding else "Hold to turn the press crank, shortcut T"
		pickup_button.visible = not _anvil.is_empty() and not sliding
		pickup_button.disabled = not ready or int(_exit_drop().get("products", 0)) < 1
		pickup_button.tooltip_text = "%s · P" % ("Wait for the character" if not ready else \
			"No formed plate at the selected exit" if _exit_drop().is_empty() else \
			"Pick up the formed plate at the selected exit")
		pickup_button.accessibility_name = "Pick up formed plate from the selected exit, shortcut P"
		recover_work_button.visible = not _anvil.is_empty() and not sliding
		recover_work_button.disabled = not ready or _work_drop().is_empty()
		var recover_action := "Pick up the copper offcut beneath the %s" % work_face if int(_work_drop().get("offcuts", 0)) > 0 else \
			"Recover material beneath the %s" % work_face if not _work_drop().is_empty() else "No material beneath the %s to recover" % work_face
		recover_work_button.tooltip_text = "%s · U" % ("Wait for the character" if not ready else recover_action)
		recover_work_button.accessibility_name = "%s, shortcut U" % recover_action
		_refresh_workbed_inventory(ready)
		if press_section.visible:
			_update_context_size()
		if changed_target:
			open_context()

	func _receiver_route_status(snapshot: Dictionary) -> String:
		var placed: Dictionary = snapshot.get("placed_components", {})
		var spans: Dictionary = snapshot.get("belt_spans", {})
		var shafts: Dictionary = snapshot.get("transmission_parts", {})
		var motion: Dictionary = snapshot.get("motion", {})
		for collector: Variant in snapshot.get("collector_assemblies", []):
			if not collector is Dictionary or collector.get("status") != "ready":
				continue
			var fitted: Dictionary = collector.get("parts", {})
			var frame: Dictionary = placed.get(fitted.get("frame"), {})
			var receiver: Dictionary = placed.get(fitted.get("receiver"), {})
			if not frame.get("center") is Array or not receiver.get("center") is Array:
				continue
			var frame_grid: Array = frame.center
			var tray_grid: Array = receiver.center
			if frame_grid.size() != 3 or tray_grid.size() != 3:
				continue
			var mouth: Array = []
			for axis in 3:
				mouth.append(int(frame_grid[axis]) + 4 * (int(tray_grid[axis]) - int(frame_grid[axis])))
			for span_id: Variant in spans:
				var span: Variant = spans[span_id]
				if not span is Dictionary:
					continue
				var first: Dictionary = shafts.get(span.get("from"), {})
				var last: Dictionary = shafts.get(span.get("to"), {})
				var inlet_first: bool = first.get("center", []) == mouth
				if not inlet_first and last.get("center", []) != mouth:
					continue
				var axle: int = int(first.get("axis", -1))
				var speed: Dictionary = motion.get(span.get("from"), {})
				var slots: Array = span.get("slots", [])
				var inlet_slot: int = 0 if inlet_first else slots.size() - 1
				if inlet_slot >= 0 and inlet_slot < slots.size() and slots[inlet_slot] is Dictionary:
					return "Receiver mouth: belt inlet occupied. Move or recover its blank before another transfer."
				if speed.get("state") != "rotating" or int(speed.get("numerator", 0)) == 0:
					return "Receiver mouth linked; power the belt shafts with the stream wheel."
				var first_grid: Array = first.get("center", [])
				var last_grid: Array = last.get("center", [])
				if first_grid.size() != 3 or last_grid.size() != 3 or axle not in [0, 2]:
					return "Receiver mouth linked; use a horizontal belt across its shaft axis."
				var along: int = int(last_grid[2] - first_grid[2]) if axle == 0 else int(last_grid[0] - first_grid[0])
				var positive: bool = (axle == 0 and int(speed.numerator) > 0) or (axle == 2 and int(speed.numerator) < 0)
				var toward_last: bool = positive == (along > 0)
				var outward: bool = toward_last == inlet_first
				return "Receiver mouth: belt runs outward toward its far shaft." if outward else \
					"Receiver mouth: belt runs toward the tray. Reverse the shaft rotation."
			return "Ready receiver faces %s. Place a parallel shaft at the next full tile and connect a belt outward." % _bearing(tray_grid, frame_grid)
		return "Fit a collector receiver tray before connecting its belt mouth."

	func _selected_press(snapshot: Dictionary, selected: String) -> Dictionary:
		for ready_only in [true, false]:
			for assemblies: Array in [snapshot.get("sliding_press_assemblies", []),
					snapshot.get("guided_press_assemblies", [])]:
				for value in assemblies:
					if not value is Dictionary or (ready_only and value.get("status") != "ready"):
						continue
					var parts: Dictionary = value.get("parts", {})
					if value.get("anvil") == selected or parts.values().has(selected):
						return value
		return {}

	func _sheet_stage_offers(snapshot: Dictionary, actor: String, selected: String) -> Array[Dictionary]:
		var offers: Array[Dictionary] = []
		var selected_part: Variant = snapshot.get("placed_components", {}).get(selected)
		if not selected_part is Dictionary or selected_part.get("component") != "anvil":
			return offers
		var center: Variant = selected_part.get("center")
		var carried: Variant = snapshot.get("cargo", {}).get(actor, {}).get("sheet_items")
		if not center is Array or center.size() != 3 or not carried is Array:
			return offers
		for assembly: Variant in snapshot.get("broad_press_assemblies", []):
			if not assembly is Dictionary or not assembly.get("origin") is Array or assembly.origin.size() != 3:
				continue
			var origin: Array = assembly.origin
			if center[1] != origin[1] or center[0] not in [origin[0], origin[0] + 4] \
					or center[2] not in [origin[2], origin[2] + 4]:
				continue
			for sheet: Variant in carried:
				if sheet is Dictionary and typeof(sheet.get("id")) == TYPE_INT and sheet.id > 0:
					offers.append({"center": origin.duplicate(), "sheet_id": sheet.id})
		return offers

	func _selected_broad_press(snapshot: Dictionary, selected: String) -> Dictionary:
		for assembly: Variant in snapshot.get("broad_press_assemblies", []):
			if not assembly is Dictionary or assembly.get("geometry_status") != "ready":
				continue
			var anvils: Variant = assembly.get("parts", {}).get("anvils")
			if anvils is Array and not anvils.is_empty() and anvils.has(selected):
				return assembly
		return {}

	func _broad_work_offers(snapshot: Dictionary, actor: String, selected: String) -> Array[Dictionary]:
		var offers: Array[Dictionary] = []
		var press := _selected_broad_press(snapshot, selected)
		if press.is_empty():
			return offers
		var lots: Variant = snapshot.get("cargo", {}).get(actor, {}).get("work_lots")
		if not lots is Array:
			return offers
		for lot: Variant in lots:
			if lot is Dictionary and lot.get("output_form") == "sheet" \
					and typeof(lot.get("recipe_input")) == TYPE_INT and lot.recipe_input == 3 \
					and typeof(lot.get("id")) == TYPE_INT and lot.id > 0 \
					and typeof(lot.get("remaining")) == TYPE_INT and lot.remaining >= 0:
				offers.append({"entity": str(press.parts.anvils[0]), "work_id": int(lot.id),
					"remaining": int(lot.get("remaining", 0))})
		return offers

	func _open_broad_refeed_menu() -> void:
		var popup := broad_refeed_button.get_popup()
		popup.clear()
		_broad_refeed_actor = _actor
		_broad_refeed_selected = _selected
		_broad_refeed_world = str(_snapshot.get("context", ""))
		_broad_refeed_offers = _broad_work_offers(_snapshot, _actor, _selected)
		for index: int in _broad_refeed_offers.size():
			var offer: Dictionary = _broad_refeed_offers[index]
			popup.add_item("Sheet work #%d · %d contacts remain" % [offer.work_id, offer.remaining], index)

	func _choose_broad_refeed(index: int) -> void:
		var host = _host_view()
		if host == null or index < 0 or index >= _broad_refeed_offers.size() \
				or broad_refeed_button.disabled:
			return
		var current: Variant = host.get("state")
		if not current is Dictionary or host.get("client") != _broad_refeed_actor \
				or host.get("selected") != _broad_refeed_selected \
				or str(current.get("context", "")) != _broad_refeed_world \
				or current.get("actors", {}).get(_broad_refeed_actor, {}).get("ready") != true \
				or host.get("explanation_open") == true or host.get("startup_save_pending") == true \
				or (host.has_method("_can_mutate") and host.call("_can_mutate") != true):
			return
		var chosen: Dictionary = _broad_refeed_offers[index]
		if _broad_work_offers(current, _broad_refeed_actor, _broad_refeed_selected).has(chosen):
			host.issue({"action": "refeed_broad_press_work", "entity": chosen.entity,
				"work_id": chosen.work_id})

	func _selected_shear(snapshot: Dictionary, selected: String) -> Dictionary:
		for assembly: Variant in snapshot.get("broad_shear_assemblies", []):
			if not assembly is Dictionary or int(assembly.get("sheet_id", 0)) <= 0:
				continue
			var anvils: Variant = assembly.get("parts", {}).get("anvils")
			if anvils is Array and not anvils.is_empty() and anvils.has(selected):
				return assembly
		return {}

	func _stroke_sheet() -> void:
		var host = _host_view()
		if host == null or shear_button.disabled:
			return
		var current: Variant = host.get("state")
		if not current is Dictionary or host.get("selected") != _selected \
				or host.get("client") != _actor:
			return
		var shear := _selected_shear(current, _selected)
		if shear.get("status") != "ready":
			return
		host.issue({"action": "stroke_broad_shear", "entity": str(shear.parts.anvils[0]),
			"sheet_id": int(shear.sheet_id)})

	func _open_sheet_menu() -> void:
		var popup := sheet_button.get_popup()
		popup.clear()
		_sheet_menu_actor = _actor
		_sheet_menu_selected = _selected
		_sheet_menu_world = str(_snapshot.get("context", ""))
		_sheet_offers = _sheet_stage_offers(_snapshot, _actor, _selected)
		for index: int in _sheet_offers.size():
			var offer: Dictionary = _sheet_offers[index]
			popup.add_item("Sheet #%d → %s" % [offer.sheet_id, str(offer.center)], index)

	func _choose_sheet(index: int) -> void:
		var host = _host_view()
		if host == null or index < 0 or index >= _sheet_offers.size() or sheet_button.disabled:
			return
		var current: Variant = host.get("state")
		if not current is Dictionary or host.get("client") != _sheet_menu_actor \
				or host.get("selected") != _sheet_menu_selected \
				or str(current.get("context", "")) != _sheet_menu_world \
				or current.get("actors", {}).get(_sheet_menu_actor, {}).get("ready") != true \
				or host.get("explanation_open") == true or host.get("startup_save_pending") == true \
				or (host.has_method("_can_mutate") and host.call("_can_mutate") != true):
			return
		var chosen: Dictionary = _sheet_offers[index]
		if _sheet_stage_offers(current, _sheet_menu_actor, _sheet_menu_selected).has(chosen):
			host.issue({"action": "place_sheet", "center": chosen.center.duplicate(),
				"sheet_id": chosen.sheet_id})

	func _selected_collector(snapshot: Dictionary, selected: String) -> Dictionary:
		var placed: Dictionary = snapshot.get("placed_components", {})
		var selected_part: Dictionary = placed.get(selected, {})
		for value in snapshot.get("collector_assemblies", []):
			if not value is Dictionary:
				continue
			var parts: Dictionary = value.get("parts", {})
			if parts.values().has(selected) or (selected_part.get("component") == "wooden_frame"
					and selected_part.get("center", []) == value.get("center", [])):
				return value
		return {}

	func _route() -> Dictionary:
		var routes: Array = _press.get("open_feeds", [])
		return routes[_route_index] if _route_index >= 0 and _route_index < routes.size() else {}

	func _work_center() -> Array:
		if _press.has("work_center"):
			return _press.work_center
		var anvil_center: Array = _press.get("center", [])
		return anvil_center if anvil_center.size() == 3 else []

	func _drop_at(center: Array) -> Dictionary:
		for value in _snapshot.get("dropped_material", []):
			if value is Dictionary and value.get("center") == center:
				return value
		return {}

	func _work_drop() -> Dictionary:
		return _drop_at(_work_center())

	func _exit_drop() -> Dictionary:
		var selected_exit: Array = _press.get("selected_exit", [])
		if not selected_exit.is_empty():
			return _drop_at(selected_exit)
		for route in _press.get("open_feeds", []):
			var output := _drop_at(route.get("exit", []))
			if int(output.get("products", 0)) > 0:
				return output
		return _drop_at(_route().get("exit", []))

	func _host_view():
		return _host.get_ref() if _host != null else null

	func _reclaim() -> void:
		var host = _host_view()
		if host != null and _snapshot.get("placed_components", {}).has(_selected):
			host.issue({"action": "reclaim_component", "entity": _selected})

	func _cut_collector() -> void:
		var host = _host_view()
		var collector: Dictionary = _selected_collector(_snapshot, _selected)
		var parts: Dictionary = collector.get("parts", {})
		if host != null and collector.get("status") == "ready" and parts.has("mount"):
			host.issue({"action": "turn_hand_crank", "entity": parts.mount})

	func _refresh_workbed_inventory(ready: bool) -> void:
		if inventory_section == null:
			return
		var cargo: Dictionary = _snapshot.get("cargo", {}).get(_actor, {})
		var work: Dictionary = _drop_at(_broad_press.get("origin", [])) if _inventory_broad else _work_drop()
		var output: Dictionary = work if _inventory_broad else _exit_drop()
		var bench_lots: Array = work.get("work_lots", [])
		var counts := {
			"player_raw": int(cargo.get("raw", 0)),
			"player_work": 0 if _inventory_broad else _held_work_ids.size(),
			"player_plate": int(cargo.get("products", 0)),
			"player_offcut": int(cargo.get("offcuts", 0)),
			"player_target": 0,
			"workbed_target": 0,
			"workbed_work": int(work.get("raw", 0)) + int(work.get("offcuts", 0)) + bench_lots.size(),
			"workbed_output": int(output.get("sheets", 0)) if _inventory_broad else int(output.get("products", 0)),
		}
		for key: String in counts:
			var button: WorkbedInventorySlot = inventory_slots[key]
			var count: Label = inventory_counts[key]
			count.text = str(counts[key]) if counts[key] > 0 else "·"
			button.disabled = not ready or (counts[key] == 0 and not key.ends_with("_target")) \
				or (_inventory_broad and key == "player_raw" and counts[key] < 3)
		inventory_workbed_heading.text = "ON FOUR ANVILS  →  SHEET" if _inventory_broad else "ON THE WORKBED  →  OUTLET"
		inventory_slots.workbed_target.icon = load("res://opening/assets/build-icons/broad-feed.svg") \
			if _inventory_broad else load("res://opening/assets/build-icons/press-feed.svg")
		inventory_slots.workbed_output.icon = load("res://opening/assets/build-icons/sheet.svg") \
			if _inventory_broad else load("res://opening/assets/build-icons/plate.svg")
		var selected_work := "Work #%d selected" % _held_work_id if _held_work_ids.has(_held_work_id) else "No carried work"
		inventory_slots.player_raw.tooltip_text = "Carry %d ore blanks. Select or drag three to the four-anvil workbed · F" % counts.player_raw \
			if _inventory_broad else "Carry %d ore blanks. Select or drag one to the workbed · F" % counts.player_raw
		inventory_slots.player_raw.accessibility_name = inventory_slots.player_raw.tooltip_text
		inventory_slots.player_work.tooltip_text = "%s. Select or drag to the workbed · R" % selected_work
		inventory_slots.player_work.accessibility_name = inventory_slots.player_work.tooltip_text
		inventory_slots.player_plate.tooltip_text = "%d copper plates carried" % counts.player_plate
		inventory_slots.player_plate.accessibility_name = inventory_slots.player_plate.tooltip_text
		inventory_slots.player_offcut.tooltip_text = "%d copper offcuts carried" % counts.player_offcut
		inventory_slots.player_offcut.accessibility_name = inventory_slots.player_offcut.tooltip_text
		inventory_slots.player_target.tooltip_text = "Drop workbed material here to carry it"
		inventory_slots.player_target.accessibility_name = inventory_slots.player_target.tooltip_text
		var route := _route()
		var direction := _bearing(route.get("entry", []), _work_center()) if not route.is_empty() else "clear"
		inventory_slots.workbed_target.tooltip_text = "Drop three carried blanks on four supported anvils · F" \
			if _inventory_broad else "Drop a carried blank or selected workpiece here from %s" % direction
		inventory_slots.workbed_target.accessibility_name = inventory_slots.workbed_target.tooltip_text
		var work_label := "Sheet work, %d contacts remain" % int(bench_lots[0].get("remaining", 0)) \
			if _inventory_broad and not bench_lots.is_empty() and bench_lots[0] is Dictionary else \
			"%d offcut" % int(work.get("offcuts", 0)) if int(work.get("offcuts", 0)) > 0 else \
			"%d blank" % int(work.get("raw", 0)) if int(work.get("raw", 0)) > 0 else \
			"Work, %d strokes remain" % int(bench_lots[0].get("remaining", 0)) if not bench_lots.is_empty() and bench_lots[0] is Dictionary else "Empty work face"
		inventory_slots.workbed_work.tooltip_text = "%s. Select or drag to carry · U" % work_label
		inventory_slots.workbed_work.accessibility_name = inventory_slots.workbed_work.tooltip_text
		inventory_slots.workbed_output.tooltip_text = "%d sheets on four anvils. Select or drag to carry · P" % counts.workbed_output \
			if _inventory_broad else "%d plates at outlet. Select or drag to carry · P" % counts.workbed_output
		inventory_slots.workbed_output.accessibility_name = inventory_slots.workbed_output.tooltip_text

	func _inventory_can_issue() -> bool:
		var host = _host_view()
		if host == null or not _inventory_ready or not inventory_section.visible \
				or host.get("explanation_open") == true or host.get("startup_save_pending") == true:
			return false
		if host.get("client") != _actor or host.get("selected") != _selected:
			return false
		if host.has_method("_can_mutate") and host.call("_can_mutate") != true:
			return false
		var current: Variant = host.get("state")
		return current is Dictionary and current.get("context") == _snapshot.get("context") \
			and current.get("revision") == _snapshot.get("revision") \
			and current.get("order") == _snapshot.get("order")

	func inventory_drag(source: String) -> Dictionary:
		if not _inventory_can_issue():
			return {}
		var cargo: Dictionary = _snapshot.get("cargo", {}).get(_actor, {})
		var work: Dictionary = _drop_at(_broad_press.get("origin", [])) if _inventory_broad else _work_drop()
		var output: Dictionary = work if _inventory_broad else _exit_drop()
		var route := _route()
		var selected_exit: Array = _press.get("selected_exit", [])
		var clear_route: bool = not route.is_empty() and (selected_exit.is_empty() or route.get("exit") == selected_exit)
		var wire: Dictionary = {}
		var destination := ""
		match source:
			"player_raw":
				var anvils: Array = _broad_press.get("parts", {}).get("anvils", []) if _inventory_broad else []
				if _inventory_broad and anvils.size() == 4 and work.is_empty() and int(cargo.get("raw", 0)) >= 3:
					wire = {"action": "feed_broad_press", "entity": str(anvils[0])}
					destination = "workbed"
				elif not _inventory_broad and clear_route and work.is_empty() and int(cargo.get("raw", 0)) > 0:
					wire = {"action": "feed_press", "entity": _anvil, "entry": route.entry.duplicate()}
					destination = "workbed"
			"player_work":
				if not _inventory_broad and clear_route and work.is_empty() and _held_work_id > 0 and _held_work_ids.has(_held_work_id):
					wire = {"action": "refeed_press_work", "entity": _anvil,
						"entry": route.entry.duplicate(), "work_id": _held_work_id}
					destination = "workbed"
			"workbed_work":
				var held_work: bool = int(work.get("raw", 0)) > 0 or int(work.get("offcuts", 0)) > 0 \
					or not work.get("work_lots", []).is_empty()
				if not work.is_empty() and (not _inventory_broad or held_work):
					var expected := work.duplicate(true)
					expected.erase("center")
					wire = {"action": "pickup_material", "center": work.center.duplicate(), "expected": expected}
					destination = "player"
			"workbed_output":
				if int(output.get("sheets" if _inventory_broad else "products", 0)) > 0:
					var expected := output.duplicate(true)
					expected.erase("center")
					wire = {"action": "pickup_material", "center": output.center.duplicate(), "expected": expected}
					destination = "player"
		if wire.is_empty():
			return {}
		return {"source": source, "destination": destination, "wire": wire,
			"world": _snapshot.get("context"), "revision": _snapshot.get("revision"),
			"order": _snapshot.get("order"),
			"actor": _actor, "selected": _selected}

	func inventory_can_drop(destination: String, data: Variant) -> bool:
		if not data is Dictionary or not data.has("source") or data.get("destination") != destination:
			return false
		var fresh := inventory_drag(str(data.source))
		return not fresh.is_empty() and fresh == data

	func inventory_drop(destination: String, data: Variant) -> void:
		if inventory_can_drop(destination, data):
			_host_view().issue(data.wire.duplicate(true))

	func _inventory_activate(source: String) -> void:
		var data := inventory_drag(source)
		if not data.is_empty():
			inventory_drop(data.destination, data)

	func inventory_shortcut(key: int) -> bool:
		if not inventory_section.is_visible_in_tree():
			return false
		var source: String = {KEY_F: "player_raw", KEY_R: "player_work", KEY_U: "workbed_work",
			KEY_P: "workbed_output"}.get(key, "")
		if source.is_empty():
			return false
		var data := inventory_drag(source)
		if data.is_empty():
			return false
		inventory_drop(data.destination, data)
		return true

	func _feed() -> void:
		var host = _host_view()
		var route := _route()
		if host != null and not route.is_empty() and not _anvil.is_empty():
			host.issue({"action": "feed_press", "entity": _anvil, "entry": route.entry})

	func _compact_offcuts() -> void:
		var host = _host_view()
		var route := _route()
		var parts: Dictionary = _press.get("parts", {})
		if host != null and not route.is_empty() and not _anvil.is_empty() and parts.has("shaft"):
			host.issue({"action": "compact_offcuts", "entity": _anvil,
				"entry": route.entry, "drive": parts.shaft})

	func _refeed_work() -> void:
		var host = _host_view()
		var route := _route()
		if host != null and not route.is_empty() and not _anvil.is_empty() and _held_work_id > 0:
			host.issue({"action": "refeed_press_work", "entity": _anvil,
				"entry": route.entry, "work_id": _held_work_id})

	func _turn() -> bool:
		var host = _host_view()
		var route := _route()
		var parts: Dictionary = _press.get("parts", {})
		if host != null and parts.has("slide"):
			var slide: Dictionary = _snapshot.get("placed_components", {}).get(parts.slide, {})
			var ports: Array = slide.get("input_ports", [])
			for item: Dictionary in _snapshot.get("crank_items", {}).values():
				if item.get("attached_to", "") == parts.slide and ports.has(item.get("port", [])):
					var slide_outcome: Dictionary = host.issue({"action": "turn_slide_crank",
						"entity": parts.slide, "port": item.port})
					if slide_outcome.get("accepted", false):
						return true
					break
			stop_turn_hold()
			return false
		if host != null and not route.is_empty() and parts.has("shaft"):
			var outcome: Dictionary = host.issue({"action": "turn_press_crank", "entity": _anvil,
				"drive": parts.shaft, "exit": route.exit})
			if outcome.get("accepted", false):
				return true
		stop_turn_hold()
		return false

	func press_turn_key() -> bool:
		if not turn_button.is_visible_in_tree() or turn_button.disabled:
			return false
		if turn_hold_source.is_empty():
			_start_turn_hold("key")
			turn_button.pressed.emit()
		return true

	func cycle_slide_port() -> bool:
		if not slide_port_choice.is_visible_in_tree() or slide_port_choice.item_count < 2:
			return false
		_slide_port_index = (_slide_port_index + 1) % slide_port_choice.item_count
		slide_port_choice.select(_slide_port_index)
		return true

	func cycle_feed_route() -> bool:
		if not route_choice.is_visible_in_tree() or route_choice.disabled or route_choice.item_count < 2:
			return false
		_route_index = (_route_index + 1) % route_choice.item_count
		route_choice.select(_route_index)
		return true

	func _start_turn_hold(source: String) -> void:
		if not turn_hold_source.is_empty() or not turn_button.is_visible_in_tree() or turn_button.disabled:
			return
		turn_hold_source = source
		turn_repeat_timer.start()

	func stop_turn_hold(source: String = "") -> void:
		if not source.is_empty() and turn_hold_source != source:
			return
		turn_hold_source = ""
		if turn_repeat_timer != null:
			turn_repeat_timer.stop()

	func _repeat_turn() -> void:
		if turn_hold_source.is_empty() or not turn_button.is_visible_in_tree() or turn_button.disabled:
			stop_turn_hold()
			return
		if not _turn():
			stop_turn_hold()
			return
		if not turn_hold_source.is_empty() and turn_button.is_visible_in_tree() and not turn_button.disabled:
			turn_repeat_timer.start()

	func _pickup_at(drop: Dictionary) -> void:
		var host = _host_view()
		if host != null and not drop.is_empty():
			var expected := drop.duplicate(true)
			expected.erase("center")
			host.issue({"action": "pickup_material", "center": drop.center,
				"expected": expected})

	func _pickup_exit() -> void:
		_pickup_at(_exit_drop())

	func _recover_work() -> void:
		_pickup_at(_work_drop())
