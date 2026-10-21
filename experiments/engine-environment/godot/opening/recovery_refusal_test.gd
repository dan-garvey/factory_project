extends SceneTree
## Invented outcomes and projections only. Views never enter the scene tree,
## so neither a real Model nor a Session, body or game scene is created.

const RecoveryActions = preload("res://opening/recovery_actions.gd")
const RECOVERY_TEXT := "Use the material menu to recover its contents, then dismantle the machine."

class StubModel extends RefCounted:
	var snapshot: Dictionary
	var reply: Dictionary
	var submitted: Array[Dictionary] = []
	func projection() -> Dictionary:
		return snapshot.duplicate(true)
	func command(wire: Dictionary) -> Dictionary:
		submitted.append(wire.duplicate(true))
		return reply.duplicate(true)

class StubSession extends RefCounted:
	var ready := true
	func is_ready() -> bool:
		return ready

class OfflineView extends "res://opening/opening.gd":
	var messages: Array[Dictionary] = []
	func _message(text: String, refused: bool = false) -> void:
		messages.append({"text": text, "refused": refused})
	func _refresh() -> void:
		pass

class SharedView extends "res://opening/shared_opening.gd":
	var messages: Array[Dictionary] = []
	func _message(text: String, refused: bool = false) -> void:
		messages.append({"text": text, "refused": refused})
	func _refresh_ui() -> void:
		pass

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

func _snapshot(native_option: Variant = true) -> Dictionary:
	return {"context": "invented-refusal", "revision": 4, "order": 3,
		"options": {"native": native_option, "physical": true},
		"actors": {"P": {"ready": true}},
		"entities": {"collector": {"kind": "collector"}},
		"stock": {"collector": 1, "belt": 0, "input": 0, "held": 0, "output": 0},
		"cargo": {"P": {"raw": 0, "products": 0, "work_lots": []}},
		"inventories": {"P": 0}, "parts": {"collector": 0}}

func _mount(view: Node, kind: String) -> void:
	if kind == "missing":
		return
	var control = RecoveryActions.new() if kind == "current" else VBoxContainer.new()
	view.set("recovery_actions", control)
	if kind == "current":
		control.configure(view)

func _dispose(view: Node) -> void:
	var control: Variant = view.get("recovery_actions")
	if control != null:
		control.free()
	view.free()

func _offline(label: String, native_option: Variant, reply: Dictionary,
		expected: String, helper_kind: String = "current", legacy: bool = false) -> void:
	var view := OfflineView.new()
	view.state = _snapshot(native_option)
	view.selected = "collector"
	view.legacy_fixture = legacy
	var stub := StubModel.new()
	stub.snapshot = view.state.duplicate(true)
	stub.reply = reply.duplicate(true)
	view.model = stub
	_mount(view, helper_kind)
	var before: Dictionary = view.state.duplicate(true)
	var result: Dictionary = view.issue({"action": "remove", "entity": "collector"})
	_expect(view.messages == [{"text": expected, "refused": not bool(reply.accepted)}], label + ": feedback")
	_expect(result == reply and stub.submitted.size() == 1 and view.request_sequence == 1,
		label + ": exactly the original request and result")
	_expect(view.state == before and stub.snapshot == before, label + ": no material or projection mutation")
	_dispose(view)

func _shared(label: String, native_option: Variant, reason: String, expected: String,
		barrier: String = "confirmed", helper_kind: String = "current", uncertain: bool = false) -> void:
	var view := SharedView.new()
	view.client = "P"
	view.selected = "collector"
	view.state = _snapshot(native_option)
	var stub := StubSession.new()
	stub.ready = barrier != "disconnected"
	view.session = stub
	_mount(view, helper_kind)
	var result: Dictionary = {"accepted": false, "reason": reason,
		"request": "original-request", "client": "P", "context": view.state.context,
		"revision": 4, "order": 4 if barrier == "newer" else 3}
	if uncertain:
		result["uncertain"] = true
	view.pending_actions = {"original-request": {
		"action": {"action": "remove", "entity": "collector"},
		"outcome": {} if barrier == "pending" else result}}
	var before: Dictionary = view.state.duplicate(true)
	view._settle_pending()
	if barrier == "newer":
		_expect(view.messages == [{"text": "Server decision received. Waiting for the current worksite…", "refused": false}],
			label + ": wait for the confirmed projection")
	elif barrier in ["pending", "disconnected"]:
		_expect(view.messages.is_empty(), label + ": no invented final feedback")
	else:
		_expect(view.messages == [{"text": expected, "refused": true}], label + ": feedback")
	_expect(view.pending_actions.size() == (0 if barrier == "confirmed" else 1), label + ": original settlement barrier")
	_expect(view.request_sequence == 0 and view.state == before and view.model == null,
		label + ": no request, material mutation or live client Model")
	_dispose(view)

func _run() -> void:
	var occupied: Dictionary = {"accepted": false, "reason": "occupied_target"}
	for reason: String in ["collector_below_source", "source_too_deep", "invalid_source_surface"]:
		var expected: String = {
			"collector_below_source": "Raise the collector above the mineral surface, using a foundation if needed.",
			"source_too_deep": "Lower the collector: the mineral surface is beyond its extraction depth.",
			"invalid_source_surface": "The mineral surface is unavailable. Choose another place on the deposit."}[reason]
		_offline("offline mineral " + reason, true, {"accepted": false, "reason": reason}, expected)
		_shared("shared mineral " + reason, true, reason, expected)
	_offline("uncertain mineral delivery", true, {"accepted": false, "reason": "source_too_deep", "uncertain": true},
		"That action is unavailable here.")
	_offline("offline native occupied", true, occupied, RECOVERY_TEXT)
	_offline("offline historical profile", false, occupied, "That action is unavailable here.")
	_offline("offline explicit legacy", true, occupied, "That action is unavailable here.", "current", true)
	_offline("offline nonboolean native flag", 1, occupied, "That action is unavailable here.")
	_offline("offline unrelated refusal", true, {"accepted": false, "reason": "out_of_reach"},
		"Move closer to the target before building or interacting.")
	_offline("offline uncertain delivery", true, {"accepted": false, "reason": "occupied_target", "uncertain": true},
		"That action is unavailable here.")
	_offline("offline nonboolean acceptance", true, {"accepted": 0, "reason": "occupied_target"},
		"That action is unavailable here.")
	_offline("offline accepted command", true, {"accepted": true, "reason": "occupied_target"},
		"Part returned to your carried kit.")
	_offline("offline missing helper", true, occupied, "That action is unavailable here.", "missing")
	_offline("offline older helper", true, occupied, "That action is unavailable here.", "older")
	_shared("shared native occupied", true, "occupied_target", RECOVERY_TEXT)
	_shared("shared historical profile", false, "occupied_target", "Not applied: occupied_target")
	_shared("shared unrelated refusal", true, "out_of_reach",
		"Not applied: move closer to the target before building or interacting.")
	_shared("shared uncertain delivery", true, "occupied_target", "Not applied: occupied_target", "confirmed", "current", true)
	_shared("shared missing helper", true, "occupied_target", "Not applied: occupied_target", "confirmed", "missing")
	_shared("shared older helper", true, "occupied_target", "Not applied: occupied_target", "confirmed", "older")
	_shared("shared future projection", true, "occupied_target", "", "newer")
	_shared("shared outcome pending", true, "occupied_target", "", "pending")
	_shared("shared disconnected", true, "occupied_target", "", "disconnected")
	print(JSON.stringify({"status": "pass" if failures.is_empty() else "fail",
		"evidence": "isolated_recovery_refusal_ui", "checks": checks, "failures": failures,
		"fixtures": "invented responses and projections; inert Model and Session stubs",
		"real_models": 0, "real_sessions": 0, "native_bodies": 0, "game_scenes": 0}))
	quit(0 if failures.is_empty() else 1)
