extends SceneTree
## Invented UI records only. No Model, Session, native body or game scene runs.

const RecoveryActions = preload("res://opening/recovery_actions.gd")
const LARGE_ID: int = 9007199254740993
const SHEET_ID: int = LARGE_ID + 1

class TestHost extends RefCounted:
	var data: Dictionary
	var commands: Array[Dictionary]
	var legacy_fixture: bool = false
	var explanation_open: bool = false
	var startup_save_pending: bool = false
	var state: Dictionary:
		get: return data.snapshot
	var client: String:
		get: return data.actor
	var selected: String:
		get: return data.selected
	func _can_mutate() -> bool:
		return data.usable
	func issue(command: Dictionary) -> Dictionary:
		commands.append(command.duplicate(true))
		return {"accepted": false, "reason": "invented_ui_submission"}

var fixture: Dictionary
var controls
var host: TestHost
var sent: Array[Dictionary] = []
var checks: int = 0
var failed: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)

func _new_fixture() -> void:
	if controls != null:
		controls.free()
	fixture = {"actor": "P", "selected": "collector", "usable": true, "snapshot": {
		"context": "ui-world", "options": {"native": true},
		"actors": {"P": {"ready": true}, "Q": {"ready": true}},
		"cargo": {"P": {"raw": 0, "products": 0, "work_lots": []},
			"Q": {"raw": 1, "products": 2, "work_lots": []}},
		"entities": {"collector": {"kind": "collector"}, "belt": {"kind": "belt"},
			"press": {"kind": "processor"}, "wheel": {"kind": "wheel"}},
		"stock": {"collector": 1, "belt": 0, "input": 0, "held": 0, "output": 0}}}
	sent.clear()
	host = TestHost.new()
	host.data = fixture
	host.commands = sent
	controls = RecoveryActions.new()
	root.add_child(controls)
	controls.configure(host)

func _open() -> PopupMenu:
	controls.action_button.get_popup().about_to_popup.emit()
	return controls.action_button.get_popup()

func _choose(action: String, work_id: int = 0) -> void:
	var popup: PopupMenu = controls.action_button.get_popup()
	for index: int in range(popup.item_count):
		var metadata: Dictionary = popup.get_item_metadata(index)
		if metadata.wire.action == action and (action not in ["insert_work", "load_belt_slot"] or metadata.wire.work_id == work_id):
			popup.id_pressed.emit(popup.get_item_id(index))
			return
	_expect(false, "The expected explicit menu action is missing.")

func _collector_recovery() -> void:
	_new_fixture()
	var before: Dictionary = fixture.duplicate(true)
	_expect(controls.visible and not controls.action_button.disabled, "A filled Collector exposes recovery without a Press route.")
	var popup: PopupMenu = _open()
	_expect(popup.item_count == 1, "An actor without cargo has only the selected holder's recovery action.")
	_choose("recover")
	_expect(sent == [{"action": "recover", "entity": "collector"}], "Recovery emits the existing target-only action.")
	_expect(fixture == before, "Rendering and submission do not move or predict material.")
	controls.refresh()
	controls.refresh()
	_expect(sent.size() == 1, "Refresh never retries a material command.")
	fixture.snapshot.stock.collector = 0
	controls.refresh()
	_expect(not controls.visible, "An empty holder and empty carried cargo add no clutter.")

func _raw_and_whole_work() -> void:
	_new_fixture()
	fixture.selected = "press"
	fixture.snapshot.stock = {"collector": 0, "belt": 0, "input": 1, "held": 1, "output": 1}
	fixture.snapshot.cargo.P = {"raw": 2, "products": 1, "work_lots": [
		{"id": LARGE_ID, "recipe_input": 1, "cycle_ticks": 4, "remaining": 2},
		{"id": 3, "recipe_input": 1, "cycle_ticks": 4, "remaining": 0}]}
	var before: Dictionary = fixture.duplicate(true)
	controls.refresh()
	var popup: PopupMenu = _open()
	_expect(popup.item_count == 4, "Raw, partial work, ready work and machine recovery remain separate choices.")
	_expect("2 blanks" in controls.action_button.tooltip_text and "1 plate" in controls.action_button.tooltip_text and "2 workpieces" in controls.action_button.tooltip_text, "Carried forms remain separate in the compact control's tooltip.")
	_expect("2 ticks remaining" in popup.get_item_text(2) and "ready" in popup.get_item_text(3), "Partial and blocked-ready work remain distinguishable.")
	_choose("insert_raw")
	_choose("insert_work", LARGE_ID)
	_choose("insert_work", 3)
	_expect(sent == [{"action": "insert_raw", "entity": "press", "amount": 1},
		{"action": "insert_work", "entity": "press", "work_id": LARGE_ID},
		{"action": "insert_work", "entity": "press", "work_id": 3}], "Only original integer amounts and whole-work identities enter the wire.")
	_expect(typeof(sent[1].work_id) == TYPE_INT and sent[1].work_id == LARGE_ID, "A work identity above two to the fifty-third is not rounded.")
	_expect(fixture == before, "The view never replaces a recipe, progress value or holder.")
	fixture.selected = "belt"
	controls.refresh()
	popup = _open()
	_expect(popup.item_count == 1 and popup.get_item_metadata(0).wire.action == "insert_raw", "A Belt never offers whole-work insertion or product conversion.")
	fixture.selected = "wheel"
	controls.refresh()
	_expect(controls.action_button.disabled, "A source or mechanical part is not a recoverable material holder.")

func _changed_context_and_disabled_views() -> void:
	for boundary: String in ["help", "startup", "pending", "disconnected", "unready", "actor", "world", "selection"]:
		_new_fixture()
		_open()
		match boundary:
			"help": host.explanation_open = true
			"startup": host.startup_save_pending = true
			"pending", "disconnected": fixture.usable = false
			"unready": fixture.snapshot.actors.P.ready = false
			"actor": fixture.actor = "Q"
			"world": fixture.snapshot.context = "another-world"
			"selection": fixture.selected = "belt"
		controls.refresh()
		_choose("recover")
		_expect(sent.is_empty(), "An open menu cannot submit after the %s boundary changes." % boundary)
		if boundary in ["help", "startup", "pending", "disconnected", "unready"]:
			_expect(controls.action_button.disabled, "An unavailable view disables its material action.")
	_new_fixture()
	fixture.snapshot.options.native = false
	controls.refresh()
	_expect(not controls.visible and controls.action_button.disabled, "The scripted and legacy profiles do not gain unimplemented actions.")
	fixture.snapshot.options.native = true
	host.legacy_fixture = true
	controls.refresh()
	_expect(not controls.visible and controls.action_button.disabled, "The legacy view cannot enable native recovery from a mismatched flag.")

func _stale_holdings_do_not_retarget() -> void:
	_new_fixture()
	fixture.selected = "press"
	fixture.snapshot.stock.collector = 0
	fixture.snapshot.cargo.P.work_lots = [
		{"id": LARGE_ID, "recipe_input": 1, "cycle_ticks": 4, "remaining": 2},
		{"id": 3, "recipe_input": 1, "cycle_ticks": 4, "remaining": 0}]
	controls.refresh()
	_open()
	fixture.snapshot.cargo.P.work_lots.remove_at(0)
	controls.refresh()
	_choose("insert_work", LARGE_ID)
	_expect(sent.is_empty(), "A missing original workpiece cannot become the next workpiece at the same menu index.")
	_open()
	_choose("insert_work", 3)
	_expect(sent == [{"action": "insert_work", "entity": "press", "work_id": 3}], "A newly opened menu can explicitly choose the remaining ready workpiece.")
	_new_fixture()
	_open()
	fixture.snapshot.stock.collector = 0
	_choose("recover")
	_expect(sent.is_empty(), "A holder emptied after menu opening cannot submit stale recovery.")
	_new_fixture()
	fixture.snapshot.cargo.P.raw = 1
	controls.refresh()
	_open()
	fixture.snapshot.cargo.P.raw = 0
	_choose("insert_raw")
	_expect(sent.is_empty(), "Spent carried raw cannot be replaced by another material form.")

func _malformed_projection_is_not_coerced() -> void:
	for boundary: String in ["float_raw", "boolean_products", "float_work_id", "duplicate_work_id", "invalid_remaining", "missing_actor", "missing_stock"]:
		_new_fixture()
		match boundary:
			"float_raw": fixture.snapshot.cargo.P.raw = 1.0
			"boolean_products": fixture.snapshot.cargo.P.products = true
			"float_work_id": fixture.snapshot.cargo.P.work_lots = [{"id": 3.0, "recipe_input": 1, "cycle_ticks": 4, "remaining": 2}]
			"duplicate_work_id": fixture.snapshot.cargo.P.work_lots = [
				{"id": 3, "recipe_input": 1, "cycle_ticks": 4, "remaining": 2},
				{"id": 3, "recipe_input": 1, "cycle_ticks": 4, "remaining": 0}]
			"invalid_remaining": fixture.snapshot.cargo.P.work_lots = [{"id": 3, "recipe_input": 1, "cycle_ticks": 4, "remaining": -1}]
			"missing_actor": fixture.snapshot.actors.erase("P")
			"missing_stock": fixture.snapshot.stock.erase("held")
		controls.refresh()
		_expect(not controls.visible and controls.action_button.disabled, "The %s projection is unavailable rather than coerced." % boundary)
		var popup: PopupMenu = _open()
		_expect(popup.item_count == 0 and sent.is_empty(), "An invalid projection emits no material intent.")

func _belt_span_recovery() -> void:
	_new_fixture()
	fixture.selected = "span"
	var item := {"raw": 0, "products": 0, "work_lots": [{"id": LARGE_ID, "recipe_input": 1, "cycle_ticks": 4, "remaining": 2, "completed_subticks": 123, "work_remainder": 1, "work_remainder_denominator": 3}]}
	fixture.snapshot.belt_spans = {"span": {"slots": [null, item, {"raw": 1, "products": 0, "work_lots": []}]}}
	controls.refresh()
	var popup := _open()
	_expect(controls.visible and popup.item_count == 2, "Only occupied span positions offer recovery.")
	fixture.snapshot.belt_spans.span.slots[1] = null
	_choose("recover_belt_slot")
	_expect(sent.is_empty(), "A moved workpiece cannot be replaced by the next menu item.")
	fixture.snapshot.belt_spans.span.slots[1] = item
	_open()
	_choose("recover_belt_slot")
	_expect(sent == [{"action": "recover_belt_slot", "entity": "span", "slot": 1, "expected": item}], "The request retains the original whole workpiece and position.")

func _belt_loading() -> void:
	_new_fixture()
	fixture.selected = "span"
	fixture.snapshot.cargo.P = {"raw": 1, "products": 1, "work_lots": [
		{"id": LARGE_ID, "recipe_input": 1, "cycle_ticks": 4, "remaining": 2}],
		"sheet_items": [{"id": SHEET_ID, "rotation": 2}]}
	fixture.snapshot.transmission_parts = {"a": {"axis": 2, "center": [0, 4, 0]}, "b": {"axis": 2, "center": [4, 4, 0]}}
	fixture.snapshot.belt_spans = {"span": {"from": "a", "to": "b", "slots": [null, null]}}
	controls.refresh()
	var popup := _open()
	_expect(controls.visible and popup.item_count == 8
		and "1 sheet" in controls.action_button.tooltip_text,
		"Each empty horizontal position offers the carried sheet as one identified broad item.")
	_choose("load_belt_slot", LARGE_ID)
	_expect(sent == [{"action": "load_belt_slot", "entity": "span", "slot": 0, "item": "work", "work_id": LARGE_ID}],
		"The selected workpiece identity is sent without rounding or prediction.")
	sent.clear()
	_open()
	_choose("load_belt_slot", SHEET_ID)
	_expect(sent == [{"action": "load_belt_slot", "entity": "span", "slot": 0,
		"item": "sheet", "work_id": SHEET_ID}],
		"Attempting the narrow belt preserves the finished sheet identity for native fit refusal.")
	sent.clear()
	_open()
	fixture.snapshot.cargo.P.sheet_items.clear()
	_choose("load_belt_slot", SHEET_ID)
	_expect(sent.is_empty(), "A sheet removed after menu opening cannot retarget another carried item.")
	fixture.snapshot.cargo.P.sheet_items = [{"id": SHEET_ID, "rotation": 2}]
	_open()
	fixture.snapshot.belt_spans.span.slots[0] = {"raw": 1, "products": 0, "work_lots": []}
	_choose("load_belt_slot", LARGE_ID)
	_expect(sent.is_empty(), "A slot occupied after opening cannot retarget the pending load.")
	fixture.snapshot.transmission_parts.b.center = [0, 8, 0]
	controls.refresh()
	popup = _open()
	_expect(popup.item_count == 1, "A vertical power-only belt offers recovery but no loading.")
	fixture.snapshot.transmission_parts.b.center = [4, 4, 0]
	fixture.snapshot.transmission_parts.a.axis = 1
	controls.refresh()
	popup = _open()
	_expect(popup.item_count == 1, "A sideways power-only belt offers no loading.")
	fixture.snapshot.transmission_parts.a.axis = 2
	fixture.snapshot.cargo.P.raw = 0
	fixture.snapshot.cargo.P.products = 0
	fixture.snapshot.cargo.P.work_lots.clear()
	controls.refresh()
	popup = _open()
	_expect(controls.visible and not controls.action_button.disabled and popup.item_count == 2,
		"A sheet-only actor can inspect the occupied slot and attempt the one clear belt position.")
	_choose("load_belt_slot", SHEET_ID)
	_expect(sent == [{"action": "load_belt_slot", "entity": "span", "slot": 1,
		"item": "sheet", "work_id": SHEET_ID}],
		"The sheet-only menu keeps the original identity and the selected open position.")

func _loose_channel_handling() -> void:
	_new_fixture()
	var loose = RecoveryActions.LooseMaterialControls.new()
	root.add_child(loose)
	fixture.snapshot.dropped_material = [{"center": [20, 0, 0], "raw": 0,
		"products": 0, "offcuts": 0, "sheets": 1, "work_lots": [],
		"sheet_items": [{"id": SHEET_ID, "rotation": 1}]}]
	loose.configure(host)
	loose.get_popup().about_to_popup.emit()
	_expect(loose.visible and loose.get_popup().item_count == 5,
		"One confirmed loose sheet exposes pickup and four cardinal push directions through Ctrl+L.")
	_expect("east" in loose.get_popup().get_item_text(1) and
		"[24, 0, 0]" in loose.get_popup().get_item_text(1),
		"The push offer identifies its sheet and receiving square before submission.")
	loose.get_popup().id_pressed.emit(1)
	_expect(sent == [{"action": "push_channel_sheet", "from": [20, 0, 0],
		"to": [24, 0, 0], "sheet_id": SHEET_ID}],
		"The push uses the native sheet serial and a single full-cell step.")
	sent.clear()
	loose.get_popup().about_to_popup.emit()
	fixture.snapshot.dropped_material[0].sheet_items[0].id = SHEET_ID + 1
	loose.get_popup().id_pressed.emit(1)
	_expect(sent.is_empty(), "A changed loose sheet cannot receive a stale push command.")
	loose.get_popup().about_to_popup.emit()
	fixture.snapshot.context = "other-world"
	loose.get_popup().id_pressed.emit(1)
	_expect(sent.is_empty(), "A changed world cannot receive the former sheet command.")
	loose.free()

func _run() -> void:
	_collector_recovery()
	_raw_and_whole_work()
	_changed_context_and_disabled_views()
	_stale_holdings_do_not_retarget()
	_malformed_projection_is_not_coerced()
	_belt_span_recovery()
	_belt_loading()
	_loose_channel_handling()
	controls.free()
	print(JSON.stringify({"status": "fail" if failed else "pass", "evidence": "invented_recovery_ui", "checks": checks}))
	quit(1 if failed else 0)
