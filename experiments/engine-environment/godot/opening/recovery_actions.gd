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
			if not drop is Dictionary or not drop.get("center") is Array or drop.center.size() != 3 or typeof(drop.get("raw")) != TYPE_INT or drop.raw < 0 or typeof(drop.get("products")) != TYPE_INT or drop.products < 0 or not drop.get("work_lots") is Array or (drop.raw == 0 and drop.products == 0 and drop.work_lots.is_empty() and int(drop.get("offcuts", 0)) == 0 and int(drop.get("sheets", 0)) == 0):
				continue
			var point: Array = drop.center
			if typeof(point[0]) != TYPE_INT or typeof(point[1]) != TYPE_INT or typeof(point[2]) != TYPE_INT:
				continue
			var label := "%d blank(s), %d plate(s), %d workpiece(s)" % [drop.raw, drop.products, drop.work_lots.size()]
			if drop.has("offcuts"):
				label += ", %d offcut(s), %d sheet(s)" % [drop.offcuts, drop.sheets]
			get_popup().add_item("%s at %s" % [label, str(point)], _offers.size())
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
		["ram_face", "Ram face"], ["copper_shaft", "Copper shaft"],
		["copper_cog", "Copper cog"], ["wooden_workbench", "Wooden workbench"],
		["wooden_slide", "Wooden slide"], ["copper_slide", "Copper slide"],
	]
	const COLLECTOR_NEXT := {
		"missing_mount": "Fit a tool mount toward the ore deposit.",
		"missing_edge": "Fit a cutting edge beyond the mount.",
		"missing_receiver": "Fit a receiver tray beside the frame.",
		"missing_shaft": "Fit a shaft beside the receiver or behind the frame.",
		"ambiguous": "Remove the extra fitting so this collector has one shaft and receiver.",
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
	var _held_work_id := 0
	var _held_work_ids: Array[int] = []
	var _last_anvil := ""
	var reclaim_button: Button
	var reclaim_row: HBoxContainer
	var crank_button: Button
	var collector_crank_button: Button
	var collector_cut_button: Button
	var collector_status: Label
	var press_status: Label
	var feed_heading: Label
	var feed_actions: HBoxContainer
	var output_heading: Label
	var output_actions: HBoxContainer
	var route_choice: OptionButton
	var held_work_choice: OptionButton
	var feed_button: Button
	var compact_button: Button
	var refeed_work_button: Button
	var turn_button: Button
	var turn_repeat_timer: Timer
	var turn_hold_source := ""
	var pickup_button: Button
	var recover_work_button: Button
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
		reclaim_row.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_child(reclaim_row)
		host._label(reclaim_row, "RECLAIM PART", 11, Color("f4bf75"))
		reclaim_button = host._button(reclaim_row, "", _reclaim)
		_style_workshop_icon(reclaim_button, "workshop-reclaim")
		reclaim_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		reclaim_row.visible = false
		collector_section = VBoxContainer.new()
		column.add_child(collector_section)
		collector_status = host._label(collector_section, "", 12, Color("bfd1cc"))
		collector_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var collector_actions := HBoxContainer.new()
		collector_actions.alignment = BoxContainer.ALIGNMENT_CENTER
		collector_section.add_child(collector_actions)
		collector_crank_button = host._button(collector_actions, "", _crank)
		_style_workshop_icon(collector_crank_button, "workshop-crank")
		collector_crank_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		collector_cut_button = host._button(collector_actions, "", _cut_collector)
		_style_workshop_icon(collector_cut_button, "workshop-cut")
		collector_cut_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		press_section = VBoxContainer.new()
		column.add_child(press_section)
		press_status = host._label(press_section, "Select an anvil with E", 13, Color("bfd1cc"))
		press_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		route_choice = OptionButton.new()
		route_choice.name = "PressRoute"
		route_choice.item_selected.connect(func(index: int) -> void: _route_index = index)
		press_section.add_child(route_choice)
		held_work_choice = OptionButton.new()
		held_work_choice.name = "HeldPressWorkChoice"
		held_work_choice.item_selected.connect(func(index: int) -> void:
			if index >= 0 and index < _held_work_ids.size():
				_held_work_id = _held_work_ids[index])
		press_section.add_child(held_work_choice)
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
		crank_button = host._button(output_actions, "", _crank)
		_style_workshop_icon(crank_button, "workshop-crank")
		collector_section.visible = false
		press_section.visible = false
		visible = false

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
			scroller.custom_minimum_size.y = 280 if press_section.visible and _press.get("status") == "ready" \
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
		visible = snapshot.get("options", {}).get("native", false) and snapshot.has("hand_sources")
		if not visible:
			return
		var cargo: Dictionary = snapshot.get("cargo", {}).get(actor, {})
		reclaim_button.visible = snapshot.get("placed_components", {}).has(selected)
		reclaim_row.visible = reclaim_button.visible
		reclaim_button.disabled = not ready or not reclaim_button.visible
		reclaim_button.tooltip_text = "%s · Delete" % ("Reclaim selected placed part" if ready else "Wait for the character")
		reclaim_button.accessibility_name = "Reclaim selected placed part, shortcut Delete"
		var crank: Dictionary = snapshot.get("hand_crank", {})
		var collector: Dictionary = _selected_collector(snapshot, selected)
		var collector_parts: Dictionary = collector.get("parts", {})
		var receiver: Dictionary = snapshot.get("placed_components", {}).get(collector_parts.get("receiver", ""), {})
		var receiver_center: Array = receiver.get("center", [])
		var receiver_full: bool = not receiver_center.is_empty() and not _drop_at(receiver_center).is_empty()
		collector_status.visible = not collector.is_empty()
		collector_crank_button.visible = collector_status.visible and not crank.is_empty()
		collector_cut_button.visible = collector_status.visible
		if collector_status.visible:
			var collector_state := str(collector.get("status", ""))
			collector_status.text = "Collector receiver holds an ore blank. Pick it up before another cut." if receiver_full else \
				"Collector ready. Turn its fitted shaft to cut one ore blank." if collector_state == "ready" else \
				"Collector: %s" % COLLECTOR_NEXT.get(collector_state, "Choose a clear ore-deposit frame.")
			if collector_state == "ready":
				collector_status.text += "\n" + _receiver_route_status(snapshot)
			var crank_holder: String = str(crank.get("holder", ""))
			var crank_action := "Return crank to pod" if crank_holder == actor else \
				"Take pod crank" if crank_holder == "pod" else "Crank held by another worker"
			collector_crank_button.tooltip_text = "%s · T" % crank_action if crank_holder in [actor, "pod"] else crank_action
			collector_crank_button.accessibility_name = "%s, shortcut T" % crank_action if crank_holder in [actor, "pod"] else crank_action
			collector_crank_button.disabled = not ready or (crank.get("holder", "") != "pod" and crank.get("holder", "") != actor)
			collector_cut_button.disabled = not ready or collector_state != "ready" or receiver_full \
				or crank.get("holder") != actor or not collector_parts.has("shaft")
			var cut_hint := "Cut one ore blank"
			if not ready:
				cut_hint = "Wait for the character"
			elif receiver_full:
				cut_hint = "Clear the receiver"
			elif crank.get("holder") != actor:
				cut_hint = "Take the crank from the pod" if crank.get("holder") == "pod" else "Crank held by another worker"
			elif collector_state != "ready":
				cut_hint = COLLECTOR_NEXT.get(collector_state, "Complete the collector")
			collector_cut_button.tooltip_text = "%s · X" % cut_hint
			collector_cut_button.accessibility_name = "Crank held by another worker" if ready and \
				crank.get("holder") not in [actor, "pod"] else "Cut one ore blank at the selected collector, shortcut X"
		crank_button.visible = not crank.is_empty()
		crank_button.disabled = not ready or (crank.get("holder", "") != "pod" and crank.get("holder", "") != actor)
		var press_crank_holder: String = str(crank.get("holder", ""))
		var press_crank_action := "Return crank to pod" if press_crank_holder == actor else \
			"Take pod crank" if press_crank_holder == "pod" else "Crank held by another worker"
		crank_button.tooltip_text = "%s · C" % press_crank_action if press_crank_holder in [actor, "pod"] else press_crank_action
		crank_button.accessibility_name = "%s, shortcut C" % press_crank_action if press_crank_holder in [actor, "pod"] else press_crank_action
		_press = _selected_press(snapshot, selected)
		_anvil = str(_press.get("anvil", ""))
		var selected_kind: String = str(snapshot.get("placed_components", {}).get(selected, {}).get("component", ""))
		if _anvil.is_empty() and selected_kind == "anvil":
			_anvil = selected
		if _anvil != _last_anvil:
			_route_index = 0
			_last_anvil = _anvil
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
		_held_work_ids.clear()
		held_work_choice.clear()
		for lot in cargo.get("work_lots", []):
			if lot is Dictionary and int(lot.get("id", 0)) > 0:
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
				advice = "Pick up the copper offcut beneath the ram before feeding again." if int(work.get("offcuts", 0)) > 0 \
					else "Exit holds a plate; pick it up, then turn again." if int(exit_drop.get("products", 0)) > 0 \
					else "Turn the crank to advance retained work."
				var work_lots: Array = work.get("work_lots", [])
				if int(work.get("offcuts", 0)) == 0 and not work_lots.is_empty() and work_lots[0] is Dictionary:
					var cycle: int = int(work_lots[0].get("cycle_ticks", 0))
					var remaining: int = int(work_lots[0].get("remaining", 0))
					if cycle > 0 and remaining > 0 and remaining <= cycle:
						if exit_drop.is_empty():
							advice = "Work stroke: %d / %d steps. Hold T or the turn icon." % [cycle - remaining, cycle]
						else:
							advice = "Exit holds a plate; stroke %d / %d steps. Pick it up before the final step." % [cycle - remaining, cycle]
			press_status.text = "Press ready · %d clear feed routes. %s" % [routes.size(), advice]
		else:
			press_status.text = {
				"anvil": "Anvil · work support",
				"ram_face": "Ram face · contact tool",
				"sliding_guide": "Guide · guided motion",
			}.get(selected_kind, "Placed part")
		var active_press := status == "ready"
		feed_heading.visible = active_press
		feed_actions.visible = active_press
		output_heading.visible = active_press
		output_actions.visible = active_press
		route_choice.visible = active_press and not routes.is_empty()
		var can_operate := ready and status == "ready" and not routes.is_empty()
		feed_button.visible = not _anvil.is_empty()
		feed_button.disabled = not can_operate or int(cargo.get("raw", 0)) < 1 or not _work_drop().is_empty()
		var operate_cause := "Wait for the character" if not ready else "Complete the guided press and choose a clear feed route"
		feed_button.tooltip_text = "%s · F" % (operate_cause if not can_operate else \
			"Carry an ore blank" if int(cargo.get("raw", 0)) < 1 else \
			"Clear the work face beneath the ram" if not _work_drop().is_empty() else \
			"Feed one carried ore blank")
		feed_button.accessibility_name = "Feed one carried ore blank, shortcut F"
		compact_button.visible = not _anvil.is_empty() and int(cargo.get("offcuts", 0)) > 0
		compact_button.disabled = not can_operate or int(cargo.get("offcuts", 0)) < 4 \
			or crank.get("holder") != actor or not _work_drop().is_empty() \
			or not _press.get("parts", {}).has("shaft")
		compact_button.tooltip_text = "Compact four carried copper offcuts into one stock blank at this press. Hold the crank and clear the work face. [%d/4]  B" % mini(4, int(cargo.get("offcuts", 0)))
		compact_button.accessibility_name = "Compact four carried copper offcuts into one blank, shortcut B"
		held_work_choice.visible = active_press and not _held_work_ids.is_empty()
		refeed_work_button.visible = held_work_choice.visible
		refeed_work_button.disabled = not can_operate or not _work_drop().is_empty()
		refeed_work_button.tooltip_text = "%s · R" % (operate_cause if not can_operate else \
			"Clear the work face beneath the ram" if not _work_drop().is_empty() else \
			"Reinsert the selected held work")
		refeed_work_button.accessibility_name = "Reinsert selected held work, shortcut R"
		turn_button.visible = not _anvil.is_empty()
		turn_button.disabled = not can_operate or crank.get("holder") != actor or _work_drop().is_empty() \
			or int(_work_drop().get("offcuts", 0)) > 0
		if changed_target or turn_button.disabled or not turn_button.visible:
			stop_turn_hold()
		turn_button.tooltip_text = "%s · T" % (operate_cause if not can_operate else \
			("Take the crank from the pod" if crank.get("holder") == "pod" else "Crank held by another worker") if crank.get("holder") != actor else \
			"Feed or reinsert work beneath the ram" if _work_drop().is_empty() else \
			"Pick up the copper offcut beneath the ram" if int(_work_drop().get("offcuts", 0)) > 0 else \
			"Exit holds a plate; turn until blocked, then pick it up" if not _exit_drop().is_empty() else \
			"Hold T or the icon to turn the crank; release to stop")
		turn_button.accessibility_name = "Crank held by another worker" if ready and can_operate and \
			crank.get("holder") not in [actor, "pod"] else "Hold to turn the guided press crank, shortcut T"
		pickup_button.visible = not _anvil.is_empty()
		pickup_button.disabled = not ready or _exit_drop().is_empty()
		pickup_button.tooltip_text = "%s · P" % ("Wait for the character" if not ready else \
			"No formed plate at the selected exit" if _exit_drop().is_empty() else \
			"Pick up the formed plate at the selected exit")
		pickup_button.accessibility_name = "Pick up formed plate from the selected exit, shortcut P"
		recover_work_button.visible = not _anvil.is_empty()
		recover_work_button.disabled = not ready or _work_drop().is_empty()
		var recover_action := "Pick up the copper offcut beneath the ram" if int(_work_drop().get("offcuts", 0)) > 0 else \
			"Recover material beneath the ram" if not _work_drop().is_empty() else "No material beneath the ram to recover"
		recover_work_button.tooltip_text = "%s · U" % ("Wait for the character" if not ready else recover_action)
		recover_work_button.accessibility_name = "%s, shortcut U" % recover_action
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
		for value in snapshot.get("guided_press_assemblies", []):
			if not value is Dictionary:
				continue
			var parts: Dictionary = value.get("parts", {})
			if value.get("anvil") == selected or parts.values().has(selected):
				return value
		return {}

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
		var route := _route()
		return _drop_at(route.get("exit", []))

	func _host_view():
		return _host.get_ref() if _host != null else null

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

	func _cut_collector() -> void:
		var host = _host_view()
		var collector: Dictionary = _selected_collector(_snapshot, _selected)
		var parts: Dictionary = collector.get("parts", {})
		if host != null and collector.get("status") == "ready" and parts.has("shaft") \
				and _snapshot.get("hand_crank", {}).get("holder") == _actor:
			host.issue({"action": "turn_hand_crank", "entity": parts.shaft})

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
