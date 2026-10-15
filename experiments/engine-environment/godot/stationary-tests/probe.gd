extends SceneTree
## S1-S6 fixture controller. No recipe or stock mutation outside model commands.

const Peer = preload("res://stationary-tests/peer.gd")
const Model = preload("res://model.gd")
var endpoint
var role := ""
var actor := ""
var port := 0
var artifact := ""
var rejoin := false
var opening := false
var phase := "joining"
var schedule: Array = []
var first_view: Dictionary = {}
var reports: Dictionary = {}
var failures: Array = []
var checks := 0
var visual_root: Node3D
var meshes: Dictionary = {}
var view_updates := 0
var stock_label: Label3D

func _initialize():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
		elif arg.begins_with("--actor="): actor = arg.trim_prefix("--actor=")
		elif arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--artifacts="): artifact = arg.trim_prefix("--artifacts=")
		elif arg == "--rejoin": rejoin = true
		elif arg == "--opening": opening = true
	call_deferred("run")

func verify(value: bool, label: String):
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func run():
	endpoint = Peer.new()
	endpoint.name = "AuthorityPeer"
	root.add_child(endpoint)
	if role == "server":
		endpoint.joined.connect(_joined)
		endpoint.queued.connect(_queued)
		endpoint.acknowledged.connect(_acknowledged)
		endpoint.lost.connect(_lost)
		if endpoint.listen(port, opening) != OK:
			push_error("Loopback listener failed")
			quit(1)
			return
		print("STATIONARY_LISTENING")
	else:
		_make_view()
		endpoint.connected_ready.connect(_ready)
		endpoint.control.connect(_control)
		endpoint.observed.connect(_observe)
		if endpoint.connect_client(port, actor) != OK:
			quit(1)

func _ready():
	if rejoin:
		endpoint.send({"action": "retrieve", "request": "take-uncertain", "amount": 1})

func _joined(name_value: String):
	if phase == "joining" and endpoint.peers.size() == 2:
		_stage("dependent", [["P", "early-connect", {"action": "connect",
			"from": "collector-1", "to": "belt-1"}]])
	elif phase == "rejoining" and name_value == "P":
		schedule = [["P", "take-uncertain", {}]]

func _stage(next_phase: String, rows: Array):
	phase = next_phase
	print("STATIONARY_PHASE " + phase)
	schedule = rows
	for row in rows:
		var intent: Dictionary = row[2].duplicate(true)
		intent["request"] = row[1]
		endpoint.tell(row[0], "submit", intent)

func _queued(_actor: String, _request: String):
	for row in schedule:
		if not endpoint.pending.has(row[0] + ":" + row[1]):
			return
	match phase:
		"dependent":
			verify(endpoint.admit("P", "early-connect").reason == "missing_entity", "dependent request refused")
			_stage("placement-conflict", [["P", "collector", {"action": "place", "kind": "collector", "cell": [0, 0]}],
				["Q", "belt-conflict", {"action": "place", "kind": "belt", "cell": [0, 0]}]])
		"placement-conflict":
			verify(endpoint.admit("P", "collector").accepted, "first controlled placement accepted")
			verify(endpoint.admit("Q", "belt-conflict").reason == "occupied", "contested placement refused")
			_stage("independent-placements", [["P", "processor", {"action": "place", "kind": "processor", "cell": [2, 0]}],
				["Q", "belt", {"action": "place", "kind": "belt", "cell": [1, 0]}]])
		"independent-placements":
			verify(endpoint.admit("Q", "belt").accepted, "independent belt accepted")
			verify(endpoint.admit("P", "processor").accepted, "independent processor accepted")
			_stage("connect", [["P", "first-link", {"action": "connect", "from": "collector-1", "to": "belt-1"}],
				["Q", "second-link", {"action": "connect", "from": "belt-1", "to": "processor-1"}]])
		"connect":
			verify(endpoint.admit("P", "first-link").accepted, "dependent link succeeds after construction")
			verify(endpoint.admit("Q", "second-link").accepted, "second real link accepted")
			if opening:
				endpoint.advance(3)
				verify(endpoint.world.projection().stock.source == 16, "opening cannot extract before a connected drive")
				_stage("opening-wheel", [["P", "wheel", {"action": "place", "kind": "wheel", "cell": [-1, 0]}],
					["Q", "wheel-contested", {"action": "place", "kind": "wheel", "cell": [-1, 0]}]])
			else:
				_quantity_conflict()
		"opening-wheel":
			verify(endpoint.admit("P", "wheel").accepted, "one carried wheel placed through a real client")
			verify(endpoint.admit("Q", "wheel-contested").reason == "occupied", "contested wheel cannot consume a second part")
			_stage("opening-drive", [["P", "drive-wheel", {"action": "connect_drive", "from": "wheel-1", "to": "collector-1"}],
				["Q", "drive-belt", {"action": "connect_drive", "from": "collector-1", "to": "belt-1"}],
				["P", "drive-press", {"action": "connect_drive", "from": "belt-1", "to": "processor-1"}]])
		"opening-drive":
			for row in schedule:
				verify(endpoint.admit(row[0], row[1]).accepted, "real opening drive connection admitted")
			verify(endpoint.world.projection().powered and endpoint.world.projection().parts.shaft == 0,
				"opening power requires the three actual debited shafts")
			for _tick in range(16):
				endpoint.advance(1)
				if endpoint.world.projection().stock.held == 1 and endpoint.world.projection().remaining == 1:
					break
			verify(endpoint.world.projection().stock.held == 1 and endpoint.world.projection().remaining == 1,
				"pause boundary contains real unfinished work")
			_stage("opening-pause", [["Q", "pause-drive", {"action": "set_power", "active": false}]])
		"opening-pause":
			verify(endpoint.admit("Q", "pause-drive").accepted, "client stops actual drive")
			var paused: Dictionary = endpoint.world.projection()
			endpoint.advance(3)
			verify(endpoint.world.projection().stock == paused.stock and endpoint.world.projection().remaining == paused.remaining,
				"power loss retains authoritative phase and every material location")
			_observe_pair("opening-paused")
		"opening-resume":
			verify(endpoint.admit("Q", "resume-drive").accepted, "client resumes same unfinished work")
			endpoint.advance(16)
			var blocked: Dictionary = endpoint.world.projection()
			verify(blocked.stock.output == 1 and blocked.stock.held == 1 and blocked.remaining == 0,
				"opening has real finished work held behind a full outlet")
			endpoint.advance(3)
			verify(endpoint.world.projection().stock == blocked.stock, "full one-item path stops finite extraction")
			_observe_pair("opening-blocked")
		"opening-running-edit":
			var before_edit: Dictionary = endpoint.world.projection()
			verify(endpoint.admit("P", "running-remove").reason == "powered", "running dismantle refused")
			verify(endpoint.admit("Q", "running-disconnect").reason == "powered", "running drive edit refused")
			verify(endpoint.world.projection().stock == before_edit.stock and endpoint.world.projection().parts == before_edit.parts,
				"refused running edits preserve materials and carried parts")
			_stage("opening-stop-edit", [["Q", "stop-edit", {"action": "set_power", "active": false}]])
		"opening-stop-edit":
			verify(endpoint.admit("Q", "stop-edit").accepted, "client establishes stopped edit boundary")
			_stage("opening-remove", [["P", "occupied-remove", {"action": "remove", "entity": "processor-1"}],
				["Q", "remove-wheel-once", {"action": "remove", "entity": "wheel-1"}]])
		"opening-remove":
			var before_remove: Dictionary = endpoint.world.projection()
			verify(endpoint.admit("P", "occupied-remove").reason == "held_stock", "stopped occupied processor cannot delete held work")
			verify(endpoint.admit("Q", "remove-wheel-once").accepted, "stopped empty wheel removed through client intent")
			verify(endpoint.world.projection().stock == before_remove.stock and endpoint.world.projection().parts.wheel == 1
				and endpoint.world.projection().parts.shaft == 1, "wheel removal refunds one wheel and one endpoint shaft without material loss")
			_stage("opening-rebuild", [["P", "rebuild-wheel", {"action": "place", "kind": "wheel", "cell": [-1, 0]}]])
		"opening-rebuild":
			var replacement: Dictionary = endpoint.admit("P", "rebuild-wheel")
			verify(replacement.accepted and replacement.entity == "wheel-2", "same-cell replacement gets the next stable generation")
			_stage("opening-retry", [["Q", "remove-wheel-once", {"action": "remove", "entity": "wheel-1"}],
				["P", "retired-wheel-link", {"action": "connect_drive", "from": "wheel-1", "to": "collector-1"}]])
		"opening-retry":
			var before_retry: Dictionary = endpoint.world.projection()
			var retried: Dictionary = endpoint.admit("Q", "remove-wheel-once")
			verify(retried.accepted and retried.duplicate and endpoint.world.projection() == before_retry,
				"old removal replay cannot remove replacement or refund again")
			verify(endpoint.admit("P", "retired-wheel-link").reason == "missing_entity", "fresh stale-reference request cannot retarget replacement")
			_stage("opening-reconnect-drive", [["P", "new-wheel-link", {"action": "connect_drive", "from": "wheel-2", "to": "collector-1"}],
				["Q", "restart-rebuilt", {"action": "set_power", "active": true}]])
		"opening-reconnect-drive":
			verify(endpoint.admit("P", "new-wheel-link").accepted, "returned shaft reconnects only new wheel identity")
			verify(endpoint.admit("Q", "restart-rebuilt").accepted, "client restarts rebuilt actual drive")
			_observe_pair("opening-rebuilt")
		"quantity-conflict":
			verify(endpoint.admit("P", "take-uncertain", true, ["P"]).accepted, "quantity winner applied with acknowledgement held")
			var before_refusal: Dictionary = endpoint.world.projection()
			verify(endpoint.admit("Q", "take-contested", false, ["P"]).reason == "unavailable_output", "same product cannot go to both clients")
			# Refusal increments order without changing revision: a distinct stale case.
			endpoint.view_state.rpc_id(endpoint.peers["Q"], before_refusal)
			verify(endpoint.world.projection().inventories.get("P", 0) == 1, "one actual inventory debit-credit")
			phase = "quantity-report"
			endpoint.tell("Q", "report", "contested")
		"rejoining":
			var before: Dictionary = endpoint.world.projection()
			var result: Dictionary = endpoint.admit("P", "take-uncertain")
			verify(result.accepted and result.duplicate, "reconnected exact request disposition retained")
			verify(endpoint.world.projection() == before, "retry leaves authority unchanged")
			phase = "duplicate-report"
			endpoint.tell("P", "report", "duplicate")
		"reuse":
			verify(endpoint.admit("P", "take-uncertain").reason == "request_reuse", "changed-payload request reuse refused")
			_stage("available-quantities", [["P", "positive-P", {"action": "retrieve", "amount": 1}],
				["Q", "positive-Q", {"action": "retrieve", "amount": 1}]])
		"available-quantities":
			_produce()
			verify(endpoint.admit("P", "positive-P").accepted, "available P product retrieved")
			_produce() # Explicit simulation advancement, not a timing sleep/retry.
			verify(endpoint.admit("Q", "positive-Q").accepted, "available Q product retrieved")
			_check_reference()
			phase = "finishing"
			endpoint.publish()
			endpoint.tell("P", "report", "final")
			endpoint.tell("Q", "report", "final")

func _observe_pair(label: String):
	phase = label
	endpoint.publish()
	endpoint.tell("P", "report", label)
	endpoint.tell("Q", "report", label)

func _quantity_conflict():
	_produce()
	first_view = endpoint.world.projection()
	endpoint.publish()
	_stage("quantity-conflict", [["P", "take-uncertain", {"action": "retrieve", "amount": 1}],
		["Q", "take-contested", {"action": "retrieve", "amount": 1}]])

func _produce():
	for _tick in range(32):
		if endpoint.world.projection().stock.output > 0:
			return
		endpoint.advance(1)
	verify(false, "declared fixture produces within 32 explicit steps")

func _acknowledged(name_value: String, label: String, data: Dictionary):
	print("STATIONARY_OBSERVED " + name_value + " " + label)
	reports[name_value + ":" + label] = data
	if label != "uncertain":
		verify(data.state == endpoint.world.projection(), name_value + " actual client converges at " + label)
	if label.begins_with("opening-"):
		if label == "opening-paused":
			verify(not data.state.powered and data.state.stock.held == 1 and data.state.remaining == 1
				and data.view.text.contains("Drive stopped"),
				name_value + " observes paused unfinished opening work")
		elif label == "opening-blocked":
			verify(data.state.powered and data.state.stock.output == 1 and data.state.stock.held == 1 and data.state.remaining == 0
				and data.view.text.contains("Drive running"),
				name_value + " observes blocked output and retained finished work")
		elif label == "opening-rebuilt":
			verify(data.state.entities.has("wheel-2") and not data.state.entities.has("wheel-1") and data.view.entities == 4
				and data.view.entity_ids.has("wheel-2") and not data.view.entity_ids.has("wheel-1")
				and data.view.text.contains("carried wheel=0 shafts=0"),
				name_value + " actual view replaces the retired wheel")
			if name_value == "Q":
				verify(data.outcomes["remove-wheel-once"].duplicate, "Q observes retained removal disposition after replacement")
		if not reports.has("P:" + label) or not reports.has("Q:" + label):
			return
		match label:
			"opening-paused":
				_stage("opening-resume", [["Q", "resume-drive", {"action": "set_power", "active": true}]])
			"opening-blocked":
				_stage("opening-running-edit", [["P", "running-remove", {"action": "remove", "entity": "processor-1"}],
					["Q", "running-disconnect", {"action": "disconnect_drive", "from": "wheel-1", "to": "collector-1"}]])
			"opening-rebuilt": _quantity_conflict()
	elif label == "contested":
		verify(not data.outcomes["take-contested"].accepted, "Q observes real quantity refusal")
		endpoint.tell("P", "report", "uncertain")
	elif label == "uncertain":
		verify(not data.outcomes.has("take-uncertain"), "P has no applied request acknowledgement")
		phase = "disconnecting"
		endpoint.tell("P", "exit", "before-disconnect")
	elif label == "stale":
		verify(data.stale_views == 2, "old revision and same-revision old order both refused")
		phase = "rejoining"
		print("STATIONARY_RECONNECT_READY")
	elif label == "duplicate":
		verify(data.outcomes["take-uncertain"].duplicate, "real rejoined client observes duplicate disposition")
		_stage("reuse", [["P", "take-uncertain", {"action": "retrieve", "amount": 2}]])
	elif label == "final":
		verify(data.view.entities == endpoint.world.projection().entities.size(), "actual client view consumes entity projection")
		if reports.has("P:final") and reports.has("Q:final"):
			# Observe each disconnect before closing the next peer. Godot's default
			# server relay otherwise notifies an already-closed peer during teardown.
			phase = "exiting-P"
			endpoint.tell("P", "exit", "final")

func _lost(name_value: String):
	print("STATIONARY_LOST " + name_value + " " + phase)
	if phase == "disconnecting" and name_value == "P":
		endpoint.advance(3)
		endpoint.publish()
		endpoint.view_state.rpc_id(endpoint.peers["Q"], first_view)
		endpoint.tell("Q", "report", "stale")
	elif phase == "exiting-P" and name_value == "P":
		phase = "exiting-Q"
		endpoint.tell("Q", "exit", "final")
	elif phase == "exiting-Q" and endpoint.peers.is_empty():
		_write("server.json", {"status": "pass" if failures.is_empty() else "fail",
			"opening": opening,
			"checks": checks, "failures": failures, "final": endpoint.world.projection(),
			"trace": endpoint.trace, "transport": endpoint.transport_events, "clients": reports})
		print("STATIONARY_AUTHORITY_PASS" if failures.is_empty() else "STATIONARY_AUTHORITY_FAIL")
		quit(0 if failures.is_empty() else 1)

func _check_reference():
	var reference = Model.new(16, "stationary-fixture-1", 1, {"opening": true}) if opening else Model.new(16, "stationary-fixture-1", 1)
	for event in endpoint.trace:
		if event.has("command"):
			verify(reference.command(event.command) == event.result, "same single-player command outcome")
		else:
			reference.advance(event.advance)
	var actual: Dictionary = endpoint.world.projection()
	verify(reference.projection() == actual, "single-player and server share actual rule path")
	var s: Dictionary = actual.stock
	verify(s.source + s.collector + s.belt + s.input + s.held + s.output + s.player == 16,
		"independent one-to-one fixture material accounting")
	verify(actual.inventories.get("P", 0) == 2 and actual.inventories.get("Q", 0) == 1,
		"independent final per-client product expectation")
	if opening:
		verify(actual.stock == {"source": 9, "collector": 1, "belt": 1, "input": 1, "held": 1, "output": 0, "player": 3},
			"independent opening final location ledger after three transfers")
		verify(actual.parts == {"collector": 0, "belt": 0, "processor": 0, "wheel": 0, "shaft": 0},
			"independent finite construction and shaft ledger after rebuild")
		verify(actual.powered and actual.entities.size() == 4 and actual.links.size() == 2 and actual.drive_links.size() == 3
			and actual.entities.has("wheel-2") and not actual.entities.has("wheel-1"), "rebuilt connected powered topology retained")

func _control(operation: String, payload):
	match operation:
		"submit": endpoint.send(payload)
		"report":
			if payload == "final" and DisplayServer.get_name() != "headless":
				await process_frame
				await process_frame
				var image: Image = root.get_texture().get_image()
				if image.save_png(artifact.path_join("client-" + actor + "-final.png")) != OK:
					quit(1)
					return
			endpoint.report(payload, {"entities": meshes.size(), "entity_ids": meshes.keys(), "updates": view_updates,
				"text": stock_label.text, "display": DisplayServer.get_name()})
		"exit":
			_write("client-" + actor + "-" + str(payload) + ".json", {
				"actor": actor, "phase": payload, "state": endpoint.state,
				"outcomes": endpoint.outcomes, "stale_views": endpoint.stale_views})
			endpoint.close()
			quit(0)

func _make_view():
	visual_root = Node3D.new()
	root.add_child(visual_root)
	var camera := Camera3D.new()
	visual_root.add_child(camera)
	camera.position = Vector3(1, 5, 6)
	camera.look_at(Vector3(1, 0, 0))
	var light := DirectionalLight3D.new()
	visual_root.add_child(light)
	light.rotation_degrees = Vector3(-60, -30, 0)
	stock_label = Label3D.new()
	visual_root.add_child(stock_label)
	stock_label.position = Vector3(1, 1.3, 0)
	stock_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	stock_label.font_size = 48

func _observe(view: Dictionary):
	view_updates += 1
	for entity_id in meshes.keys():
		if not view.entities.has(entity_id):
			meshes[entity_id].free()
			meshes.erase(entity_id)
	for entity_id in view.entities:
		if not meshes.has(entity_id):
			var mesh := MeshInstance3D.new()
			mesh.mesh = BoxMesh.new()
			mesh.scale = Vector3(0.8, 0.8, 0.8)
			var material := StandardMaterial3D.new()
			material.albedo_color = {"collector": Color.SEA_GREEN,
				"belt": Color.STEEL_BLUE, "processor": Color.GOLDENROD, "wheel": Color.SLATE_GRAY}[view.entities[entity_id].kind]
			mesh.material_override = material
			visual_root.add_child(mesh)
			meshes[entity_id] = mesh
		var cell: Array = view.entities[entity_id].cell
		meshes[entity_id].position = Vector3(cell[0], 0, cell[1])
	stock_label.text = actor + " | confirmed products: P=" + str(view.inventories.get("P", 0)) + " Q=" + str(view.inventories.get("Q", 0))
	if view.get("options", {}).get("opening", false):
		stock_label.text += "\nDrive " + ("running" if view.powered else "stopped")
		stock_label.text += " | carried wheel=" + str(view.parts.wheel) + " shafts=" + str(view.parts.shaft)

func _write(name_value: String, data: Dictionary):
	var file := FileAccess.open(artifact.path_join(name_value), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write owned probe evidence")
		quit(1)
		return
	file.store_string(JSON.stringify(data))
