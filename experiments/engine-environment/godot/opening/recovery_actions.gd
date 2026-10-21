extends VBoxContainer
## Presentation over a confirmed native projection. Only the ordinary view's
## issue callback submits commands; this control never changes material state.

var action_button: MenuButton
var _host: WeakRef

func _init() -> void:
	action_button = MenuButton.new()
	action_button.text = "Move materials…"
	action_button.tooltip_text = "Recover contents or insert carried material. Stand near the selected machine."
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
		"occupied_target": "Use the material menu to recover its contents, then dismantle the machine.",
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
	var carrying: bool = cargo.raw > 0 or not lots.is_empty()
	var occupied: bool = _has_contents(context)
	visible = carrying or occupied
	# Keep this inspector addition to one action row, including expanded Details.
	# The exact carried forms remain available without another wrapping label.
	var summary: String = "%s, %s and %s carried." % [
		_count(cargo.raw, "blank", "blanks"), _count(cargo.products, "plate", "plates"),
		_count(lots.size(), "workpiece", "workpieces")]
	action_button.tooltip_text = summary + "\nRecover contents or insert carried material. Stand near the selected machine."
	action_button.text = "Move materials…" if occupied and carrying else "Recover contents…" if occupied else "Insert carried material…"
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
	var usable: bool = host.get("explanation_open") == false and host.get("startup_save_pending") == false
	if host.has_method("_can_mutate"):
		var permission: Variant = host.call("_can_mutate")
		usable = usable and typeof(permission) == TYPE_BOOL and permission
	usable = usable and typeof(actor_sample.get("ready")) == TYPE_BOOL and actor_sample.ready
	return {"world": world_context, "actor": actor, "target": selected, "kind": kind,
		"cargo": cargo, "stock": stock, "usable": usable}

func _has_contents(context: Dictionary) -> bool:
	match context.kind:
		"collector": return context.stock.collector > 0
		"belt": return context.stock.belt > 0
		"processor": return context.stock.input > 0 or context.stock.held > 0 or context.stock.output > 0
	return false

func _offers(context: Dictionary) -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
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
