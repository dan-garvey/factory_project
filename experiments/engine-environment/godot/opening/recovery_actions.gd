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
	var carrying: bool = cargo.raw > 0 or cargo.products > 0 or not lots.is_empty()
	var occupied: bool = _has_contents(context)
	visible = carrying or occupied
	# Keep this inspector addition to one action row, including expanded Details.
	# The exact carried forms remain available without another wrapping label.
	var summary: String = "%s, %s and %s carried." % [
		_count(cargo.raw, "blank", "blanks"), _count(cargo.products, "plate", "plates"),
		_count(lots.size(), "workpiece", "workpieces")]
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
				for kind: String in ["raw", "product", "work"]:
					var ids: Array = [0] if (kind == "raw" and context.cargo.raw > 0) or (kind == "product" and context.cargo.products > 0) else []
					if kind == "work":
						for lot: Dictionary in context.cargo.work_lots:
							ids.append(lot.id)
					for id: int in ids:
						var label: String = "blank" if kind == "raw" else "plate" if kind == "product" else "workpiece %d" % id
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
		text = "Pick up loose material…  [Ctrl+L]"
		tooltip_text = "Stand near loose material, then choose it here."
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
			if not drop is Dictionary or not drop.get("center") is Array or drop.center.size() != 3 or typeof(drop.get("raw")) != TYPE_INT or drop.raw < 0 or typeof(drop.get("products")) != TYPE_INT or drop.products < 0 or not drop.get("work_lots") is Array or (drop.raw == 0 and drop.products == 0 and drop.work_lots.is_empty()):
				continue
			var point: Array = drop.center
			if typeof(point[0]) != TYPE_INT or typeof(point[1]) != TYPE_INT or typeof(point[2]) != TYPE_INT:
				continue
			get_popup().add_item("%d blank(s), %d plate(s), %d workpiece(s) at %s" % [drop.raw, drop.products, drop.work_lots.size(), str(point)], _offers.size())
			_offers.append(drop.duplicate(true))

	func _choose(id: int) -> void:
		var context := _context()
		if context.is_empty() or not context.usable or context.world != _world or context.actor != _actor or id < 0 or id >= _offers.size():
			return
		for drop: Variant in context.drops:
			if drop is Dictionary and drop == _offers[id]:
				var expected: Dictionary = _offers[id].duplicate(true)
				expected.erase("center")
				_host.get_ref().issue({"action": "pickup_material", "center": _offers[id].center.duplicate(), "expected": expected})
				return

class ArrivalAssemblyControls:
	extends PanelContainer
	## Views the native arrival cargo and sends exact component and press commands.
	## No stock, work timer, reach rule or assembly identity is owned here.

	const COMPONENTS := [
		["wooden_frame", "Wooden frame"], ["wooden_shaft", "Wooden shaft"],
		["wooden_cog", "Wooden cog"], ["receiver_tray", "Receiver tray"],
		["tool_mount", "Tool mount"], ["sliding_guide", "Sliding guide"],
		["cutting_edge", "Cutting edge"], ["anvil", "Anvil"],
		["ram_face", "Ram face"], ["softmetal_shaft", "Softmetal shaft"],
		["softmetal_cog", "Softmetal cog"],
	]
	const COMPONENT_COSTS := {
		"wooden_frame": [3, 0], "wooden_shaft": [1, 0],
		"wooden_cog": [2, 0], "receiver_tray": [2, 0],
		"tool_mount": [1, 0], "sliding_guide": [1, 0],
		"cutting_edge": [0, 1], "anvil": [0, 2],
		"ram_face": [0, 2], "softmetal_shaft": [0, 2],
		"softmetal_cog": [0, 2],
	}
	const PRESS_NEXT := {
		"missing_anvil": "Fit an anvil one height step above the frame.",
		"missing_ram": "Fit a ram face above the anvil.",
		"missing_guide": "Fit a sliding guide above the ram.",
		"missing_mount": "Fit a tool mount above the guide.",
		"missing_shaft": "Fit a shaft beside the mount at the same height.",
		"missing_cog": "Fit a cog beyond the shaft at the same height.",
	}

	var selected_component := "wooden_frame"
	var _host: WeakRef
	var _snapshot := {}
	var _actor := "P"
	var _selected := ""
	var _press := {}
	var _frame := ""
	var _route_index := 0
	var _last_frame := ""
	var _press_page := false
	var component_choice: OptionButton
	var craft_button: Button
	var recipe_label: Label
	var place_button: Button
	var reclaim_button: Button
	var crank_button: Button
	var press_status: Label
	var route_choice: OptionButton
	var feed_button: Button
	var turn_button: Button
	var pickup_button: Button
	var recover_work_button: Button
	var craft_section: VBoxContainer
	var press_section: VBoxContainer
	var craft_tab: Button
	var press_tab: Button

	func configure(host) -> void:
		_host = weakref(host)
		name = "ArrivalAssemblyControls"
		custom_minimum_size.x = 296
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 5)
		add_child(column)
		var tabs := HBoxContainer.new()
		column.add_child(tabs)
		craft_tab = host._button(tabs, "Craft parts", _show_page.bind(false))
		press_tab = host._button(tabs, "Press work", _show_page.bind(true))
		craft_tab.toggle_mode = true
		press_tab.toggle_mode = true
		craft_section = VBoxContainer.new()
		column.add_child(craft_section)
		host._label(craft_section, "FIELD WORKSHOP", 13, Color("f4bf75"))
		component_choice = OptionButton.new()
		component_choice.name = "ComponentChoice"
		for item in COMPONENTS:
			component_choice.add_item(item[1])
		component_choice.select(0)
		component_choice.item_selected.connect(_component_selected)
		craft_section.add_child(component_choice)
		recipe_label = host._label(craft_section, "", 12, Color("bfd1cc"))
		var component_actions := HBoxContainer.new()
		craft_section.add_child(component_actions)
		craft_button = host._button(component_actions, "Craft one", _craft)
		place_button = host._button(component_actions, "Place", _place)
		reclaim_button = host._button(craft_section, "Reclaim selected part", _reclaim)
		press_section = VBoxContainer.new()
		column.add_child(press_section)
		press_status = host._label(press_section, "Select a frame with E", 13, Color("bfd1cc"))
		press_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		route_choice = OptionButton.new()
		route_choice.name = "PressRoute"
		route_choice.item_selected.connect(func(index: int) -> void: _route_index = index)
		press_section.add_child(route_choice)
		var press_actions := HBoxContainer.new()
		press_section.add_child(press_actions)
		feed_button = host._button(press_actions, "Feed blank", _feed)
		turn_button = host._button(press_actions, "Turn crank", _turn)
		pickup_button = host._button(press_section, "Pick up exit product", _pickup_exit)
		recover_work_button = host._button(press_section, "Recover held work", _recover_work)
		crank_button = host._button(press_section, "Take pod crank", _crank)
		_show_page(false)
		visible = false

	func selected_name() -> String:
		return selected_component

	func press_frame_for(selected: String) -> String:
		return str(_selected_press(_snapshot, selected).get("frame", ""))

	func _show_page(press: bool) -> void:
		_press_page = press
		craft_section.visible = not press
		press_section.visible = press
		craft_tab.button_pressed = not press
		press_tab.button_pressed = press
		var scroller := get_parent() as ScrollContainer
		if scroller != null:
			scroller.custom_minimum_size.y = 260 if press else 185

	func _bearing(point: Array, center: Array) -> String:
		if point.size() != 3 or center.size() != 3:
			return "unknown"
		if point[0] > center[0]: return "east"
		if point[0] < center[0]: return "west"
		if point[2] > center[2]: return "south"
		return "north"

	func refresh(snapshot: Dictionary, actor: String, selected: String, ready: bool) -> void:
		_snapshot = snapshot
		_actor = actor
		_selected = selected
		visible = snapshot.get("options", {}).get("native", false) and snapshot.has("hand_sources")
		if not visible:
			return
		var cargo: Dictionary = snapshot.get("cargo", {}).get(actor, {})
		var components: Dictionary = cargo.get("components", {})
		var cost: Array = COMPONENT_COSTS[selected_component]
		recipe_label.text = "Needs %d timber + %d softmetal · carry %d + %d" % [
			cost[0], cost[1], cargo.get("timber", 0), cargo.get("raw", 0)]
		for index in COMPONENTS.size():
			var item: Array = COMPONENTS[index]
			component_choice.set_item_text(index, "%s  ·  %d carried" % [item[1], components.get(item[0], 0)])
		craft_button.disabled = not ready or snapshot.get("fabrication_hub", {}).is_empty() \
			or int(cargo.get("timber", 0)) < cost[0] or int(cargo.get("raw", 0)) < cost[1]
		place_button.disabled = not ready or int(components.get(selected_component, 0)) < 1
		place_button.text = "Place %s" % COMPONENTS[component_choice.selected][1]
		reclaim_button.visible = snapshot.get("placed_components", {}).has(selected)
		reclaim_button.disabled = not ready or not reclaim_button.visible
		var crank: Dictionary = snapshot.get("hand_crank", {})
		crank_button.visible = not crank.is_empty()
		crank_button.disabled = not ready or (crank.get("holder", "") != "pod" and crank.get("holder", "") != actor)
		crank_button.text = "Return crank to pod" if crank.get("holder") == actor else "Take pod crank"
		_press = _selected_press(snapshot, selected)
		_frame = str(_press.get("frame", ""))
		if _frame != _last_frame:
			_route_index = 0
			_last_frame = _frame
			_show_page(not _frame.is_empty())
		var routes: Array = _press.get("open_feeds", [])
		route_choice.clear()
		var work_center := _work_center()
		for route in routes:
			route_choice.add_item("Feed %s  →  exit %s" % [
				_bearing(route.entry, work_center), _bearing(route.exit, work_center)])
		if routes.size() > 0:
			_route_index = mini(_route_index, routes.size() - 1)
			route_choice.select(_route_index)
		var status := str(_press.get("status", ""))
		if _frame.is_empty():
			press_status.text = "Press: place a frame, then point at it and press E.\nStack anvil → ram → guide → mount; fit a shaft and cog beside the mount."
		elif status == "ready":
			var work := _work_drop()
			var exit_drop := _exit_drop()
			var advice := "Feed one carried ore blank." if int(cargo.get("raw", 0)) > 0 \
				else "Cut ore with the multitool or build a collector."
			if not work.is_empty():
				advice = "Exit holds a plate; pick it up, then turn again." if int(exit_drop.get("products", 0)) > 0 \
					else "Turn the crank to advance retained work."
			press_status.text = "Press ready · %d clear feed routes. %s" % [routes.size(), advice]
		else:
			press_status.text = "Press: %s. %s" % [status.replace("_", " "), PRESS_NEXT.get(status,
				"Clear its fitting space or choose another frame.")]
		route_choice.visible = not routes.is_empty()
		var can_operate := ready and status == "ready" and not routes.is_empty()
		feed_button.visible = not _frame.is_empty()
		feed_button.disabled = not can_operate or int(cargo.get("raw", 0)) < 1
		turn_button.visible = not _frame.is_empty()
		turn_button.disabled = not can_operate or crank.get("holder") != actor or _work_drop().is_empty()
		pickup_button.visible = not _frame.is_empty()
		pickup_button.disabled = not ready or _exit_drop().is_empty()
		recover_work_button.visible = not _frame.is_empty()
		recover_work_button.disabled = not ready or _work_drop().is_empty()

	func _selected_press(snapshot: Dictionary, selected: String) -> Dictionary:
		for value in snapshot.get("press_assemblies", []):
			if not value is Dictionary:
				continue
			var parts: Dictionary = value.get("parts", {})
			if value.get("frame") == selected or parts.values().has(selected):
				return value
		return {}

	func _route() -> Dictionary:
		var routes: Array = _press.get("open_feeds", [])
		return routes[_route_index] if _route_index >= 0 and _route_index < routes.size() else {}

	func _work_center() -> Array:
		if _press.has("work_center"):
			return _press.work_center
		var frame_center: Array = _press.get("center", [])
		return [frame_center[0], frame_center[1] + 1, frame_center[2]] if frame_center.size() == 3 else []

	func _drop_at(center: Array) -> Dictionary:
		for value in _snapshot.get("dropped_material", []):
			if value is Dictionary and value.get("center") == center:
				return value
		return {}

	func _work_drop() -> Dictionary:
		return _drop_at(_work_center())

	func _exit_drop() -> Dictionary:
		var route := _route()
		return _drop_at(route.get("exit", []))

	func _host_view():
		return _host.get_ref() if _host != null else null

	func _component_selected(index: int) -> void:
		selected_component = str(COMPONENTS[index][0])
		var host = _host_view()
		if host != null:
			refresh(host.state, host.client, host.selected, host._can_control_character())

	func _craft() -> void:
		var host = _host_view()
		if host == null:
			return
		var hub: Dictionary = _snapshot.get("fabrication_hub", {})
		if not hub.is_empty():
			host.issue({"action": "craft_component", "entity": hub.id, "component": selected_component})

	func _place() -> void:
		var host = _host_view()
		if host != null:
			host._select_tool("component")

	func _reclaim() -> void:
		var host = _host_view()
		if host != null and _snapshot.get("placed_components", {}).has(_selected):
			host.issue({"action": "reclaim_component", "entity": _selected})

	func _crank() -> void:
		var host = _host_view()
		if host == null:
			return
		var crank: Dictionary = _snapshot.get("hand_crank", {})
		if not crank.is_empty():
			host.issue({"action": "return_hand_crank" if crank.get("holder") == _actor else "take_hand_crank",
				"entity": crank.id})

	func _feed() -> void:
		var host = _host_view()
		var route := _route()
		if host != null and not route.is_empty() and not _frame.is_empty():
			host.issue({"action": "feed_press", "entity": _frame, "entry": route.entry})

	func _turn() -> void:
		var host = _host_view()
		var route := _route()
		var parts: Dictionary = _press.get("parts", {})
		if host != null and not route.is_empty() and parts.has("shaft"):
			host.issue({"action": "turn_press_crank", "entity": _frame,
				"drive": parts.shaft, "exit": route.exit})

	func _pickup_at(drop: Dictionary) -> void:
		var host = _host_view()
		if host != null and not drop.is_empty():
			host.issue({"action": "pickup_material", "center": drop.center,
				"expected": {"raw": drop.raw, "products": drop.products,
					"work_lots": drop.work_lots}})

	func _pickup_exit() -> void:
		_pickup_at(_exit_drop())

	func _recover_work() -> void:
		_pickup_at(_work_drop())
