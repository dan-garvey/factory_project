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
