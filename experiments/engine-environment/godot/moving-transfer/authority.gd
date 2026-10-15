extends "res://rotary/authority.gd"
## One inherited drive owner additionally owns this fixture's finite 3 A.
signal cut_observed(state: Dictionary)
signal transfer_completed(event: Dictionary)
signal transfer_queued(receipt: Dictionary)

const PORT := Vector3(1.4, 0.3, 0)
const INLET := Vector3(-0.55, 0, 0)
const DOCK_SIZE := Vector3(0.55, 0.10, 0.55)
const DISTANCE_LIMIT := 0.08
const FACING_LIMIT := 0.995
var dock: StaticBody3D
var _fixture := "normal"
var _dock_goal := Transform3D(Basis.IDENTITY, Vector3(1.95, 1.05, 0))
var _stock := {"carrier": 3, "receiver": 0}
var _registered := false
var _cut := 0
var _window := 0
var _inside := false
var _spent := false
var _automatic := false
var _sensor_request := 0
var _sensor_window := 0
var _order := 0
var _sample: Dictionary = {}
var _cache: Dictionary = {}
var _events: Array = []
var _transfer_queue: Array = []
var _queue_order := 0
var _active_queue := 0
var _at_cut := false

func initial_fixture(name_value: String) -> bool:
	if is_inside_tree() or name_value not in ["normal", "wrong_facing"]: return false
	_fixture = name_value
	# Initial-only facing control: the same inlet point with opposite normal.
	_dock_goal = Transform3D(Basis(Vector3.UP, PI), Vector3(0.85, 1.05, 0)) if name_value == "wrong_facing" \
		else Transform3D(Basis.IDENTITY, Vector3(1.95, 1.05, 0))
	return true

func _ready() -> void:
	super._ready()
	dock = StaticBody3D.new()
	dock.name = "FixedReceiver"
	dock.collision_layer = 1
	dock.collision_mask = 4
	_shape(dock, DOCK_SIZE)
	add_child(dock)
	dock.global_transform = _dock_goal
	get_tree().physics_frame.connect(_on_native_cut)

func _pose(value: Transform3D) -> Dictionary:
	return {"position": _array(value.origin), "basis": [_array(value.basis.x), _array(value.basis.y), _array(value.basis.z)]}

func _body(body: PhysicsBody3D, value: Transform3D) -> Dictionary:
	var shape := PhysicsServer3D.body_get_shape(body.get_rid(), 0)
	var data: Vector3 = PhysicsServer3D.shape_get_data(shape)
	var result := _pose(value)
	result.merge({"id": body.get_instance_id(), "rid": body.get_rid().get_id(),
		"space": PhysicsServer3D.body_get_space(body.get_rid()).get_id(), "shape_rid": shape.get_id(),
		"shape_type": PhysicsServer3D.shape_get_type(shape), "shape_data": _array(data),
		"layer": PhysicsServer3D.body_get_collision_layer(body.get_rid()), "mask": PhysicsServer3D.body_get_collision_mask(body.get_rid())})
	return result

func _native_geometry() -> Dictionary:
	var carrier_pose: Transform3D = PhysicsServer3D.body_get_state(bodies.B.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	var fixed_pose: Transform3D = PhysicsServer3D.body_get_state(dock.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	var outlet := carrier_pose * PORT
	var inlet := fixed_pose * INLET
	var outward := (carrier_pose.basis * Vector3.RIGHT).normalized()
	var inward := (fixed_pose.basis * Vector3.LEFT).normalized()
	var angular: Vector3 = PhysicsServer3D.body_get_state(bodies.B.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	var distance := outlet.distance_to(inlet)
	var facing := outward.dot(-inward)
	return {"frame": Engine.get_physics_frames(), "carrier": _body(bodies.B, carrier_pose), "receiver": _body(dock, fixed_pose),
		"outlet": _array(outlet), "inlet": _array(inlet), "outward": _array(outward), "inward": _array(inward),
		"distance": distance, "facing": facing, "angular_velocity": _array(angular),
		"geometric": distance <= DISTANCE_LIMIT and facing >= FACING_LIMIT,
		"initial_native": carrier_pose.origin.distance_to(Vector3(0, HEIGHT, 0)) <= ALIGN_EPSILON \
			and carrier_pose.basis.is_equal_approx(Basis.IDENTITY) and fixed_pose.is_equal_approx(_dock_goal),
		"same_world": PhysicsServer3D.body_get_space(bodies.B.get_rid()) == get_world_3d().space \
			and PhysicsServer3D.body_get_space(dock.get_rid()) == get_world_3d().space}

func _vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])

func _on_native_cut() -> void:
	# Sole window writer. Queries, retries and render refreshes cannot reopen it.
	var native := _native_geometry()
	_cut += 1
	if not _registered and native.initial_native and native.same_world: _registered = true
	var eligible: bool = _registered and native.geometric
	var entered := eligible and not _inside
	var left := not eligible and _inside
	if entered:
		_window += 1
		_spent = false
	_inside = eligible
	var delta := 0.0 if _sample.is_empty() else _vector(native.outlet).distance_to(_vector(_sample.native.outlet))
	var previous: Dictionary = {} if _sample.is_empty() else {"cut": _sample.cut, "frame": _sample.native.frame,
		"outlet": _sample.native.outlet.duplicate(), "carrier_basis": _sample.native.carrier.basis.duplicate(true)}
	var completed_basis: Array = published.get("basis", [])
	var native_axis := _vector(native.carrier.basis[0])
	var intermediate := pending and completed_basis.size() == 3 \
		and native_axis.distance_to(_vector(completed_basis[0])) > ALIGN_EPSILON \
		and native_axis.distance_to(Basis(Vector3.UP, phases.B).x) > ALIGN_EPSILON
	_sample = {"cut": _cut, "native": native, "registered": _registered, "eligible": eligible,
		"window": {"id": _window, "inside": _inside, "spent": _spent, "entered": entered, "left": left},
		"previous": previous, "port_displacement": delta, "intermediate": intermediate,
		"drive": {"pending": pending, "committed": committed, "source_phase": source_phase, "phase": phases.B,
			"requested_angle": operating_requested, "turn_tick": turn_tick, "turn_goal": turn_goal, "completed": published.duplicate(true)}}
	_at_cut = true
	var queued := _transfer_queue
	_transfer_queue = []
	for entry in queued:
		_active_queue = entry.queue_id
		_transfer(entry.intent)
	_active_queue = 0
	if _automatic and eligible and _sensor_window != _window and _stock.carrier > 0:
		_sensor_window = _window
		_sensor_request += 1
		command({"action": "transfer", "actor": "sensor", "request": "visit-" + str(_sensor_request), "kind": "A", "amount": 1})
	_at_cut = false
	cut_observed.emit(projection())

func _observation() -> Dictionary:
	var result := _sample.duplicate(true)
	if not result.is_empty(): result.window.spent = _spent
	return result

func events() -> Array:
	return _events.duplicate(true)

func _same_pose(native: Dictionary) -> bool:
	return not _sample.is_empty() and native.frame == _sample.native.frame \
		and native.carrier == _sample.native.carrier and native.receiver == _sample.native.receiver

func _emit_receipt(intent: Dictionary, disposition: Dictionary, duplicate: bool, before: Dictionary, native: Dictionary) -> Dictionary:
	var event := {"order": _order, "intent": intent.duplicate(true), "duplicate": duplicate,
		"status": "completed", "final": true, "queue_id": _active_queue,
		"disposition": disposition.duplicate(true), "before": before, "after": _stock.duplicate(true),
		"owner": get_instance_id(), "current": {"native": native, "sample": _observation()}}
	_events.append(event.duplicate(true))
	transfer_completed.emit(event.duplicate(true))
	return event

func _transfer(intent: Dictionary) -> Dictionary:
	_order += 1
	var before := _stock.duplicate(true)
	var admission_observation := _observation()
	var native := _native_geometry() if bodies.has("B") and is_instance_valid(dock) else {}
	var identity: bool = intent.get("actor") is String and intent.actor in ["P", "Q", "sensor"] \
		and intent.get("request") is String and intent.request.length() > 0 and intent.request.length() <= 64
	var key: String = intent.actor + ":" + intent.request if identity else ""
	# Historical disposition lookup precedes every current geometry/stock gate.
	if identity and _cache.has(key) and _cache[key].intent == intent:
		return _emit_receipt(intent, _cache[key].disposition, true, before, native)
	var reason := "invalid_identity"
	if identity:
		if _cache.has(key): reason = "request_payload_reuse"
		elif intent.size() != 5 or intent.get("kind") != "A" or not intent.get("amount") is int or intent.amount != 1: reason = "invalid_transfer"
		elif not _stock.carrier is int or not _stock.receiver is int or _stock.carrier < 0 or _stock.receiver < 0 or _stock.carrier + _stock.receiver != 3: reason = "invalid_stock"
		elif not _registered: reason = "native_not_ready"
		elif not _same_pose(native): reason = "native_pose_unobserved"
		elif not native.geometric or not _inside: reason = "ports_ineligible"
		elif _stock.carrier == 0: reason = "source_empty"
		elif _spent: reason = "window_spent"
		else:
			reason = "transferred"
			_stock.carrier -= 1
			_stock.receiver += 1
			_spent = true
	var disposition := {"accepted": reason == "transferred", "reason": reason, "order": _order,
		"before": before.duplicate(true), "after": _stock.duplicate(true), "observation": admission_observation, "native": native.duplicate(true)}
	if identity and not _cache.has(key): _cache[key] = {"intent": intent.duplicate(true), "disposition": disposition.duplicate(true)}
	return _emit_receipt(intent, disposition, false, before, native)

func command(intent: Dictionary) -> Dictionary:
	if intent.get("action") == "transfer":
		var cached := intent.get("actor") is String and intent.get("request") is String \
			and _cache.has(intent.actor + ":" + intent.request)
		if _registered and not _at_cut and not cached:
			_queue_order += 1
			_transfer_queue.append({"queue_id": _queue_order, "intent": intent.duplicate(true)})
			var receipt := {"status": "queued", "final": false, "queue_id": _queue_order,
				"intent": intent.duplicate(true), "submitted_frame": Engine.get_physics_frames(), "stock": _stock.duplicate(true)}
			transfer_queued.emit(receipt.duplicate(true))
			return receipt
		return _transfer(intent)
	if intent.get("action") == "automatic":
		if not intent.get("active") is bool: return _answer(false, "invalid_active")
		_automatic = intent.active
		return _answer(true, "sensor_configured")
	if intent.get("action") == "step" and not _registered: return _answer(false, "native_not_ready")
	return super.command(intent)

func projection() -> Dictionary:
	var state: Dictionary = super.projection()
	state.merge({"owner": get_instance_id(), "fixture": _fixture, "stock": _stock.duplicate(true), "order": _order,
		"automatic": _automatic, "queued_transfers": _transfer_queue.size(), "cache_entries": _cache.size(), "observation": _observation(),
		"port_rule": {"distance": DISTANCE_LIMIT, "facing": FACING_LIMIT, "one_per_window": true}})
	return state
