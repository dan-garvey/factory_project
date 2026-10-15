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
		if endpoint.listen(port) != OK:
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
			_produce()
			first_view = endpoint.world.projection()
			endpoint.publish()
			_stage("quantity-conflict", [["P", "take-uncertain", {"action": "retrieve", "amount": 1}],
				["Q", "take-contested", {"action": "retrieve", "amount": 1}]])
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
	if label == "contested":
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
			"checks": checks, "failures": failures, "final": endpoint.world.projection(),
			"trace": endpoint.trace, "transport": endpoint.transport_events, "clients": reports})
		print("STATIONARY_AUTHORITY_PASS" if failures.is_empty() else "STATIONARY_AUTHORITY_FAIL")
		quit(0 if failures.is_empty() else 1)

func _check_reference():
	var reference = Model.new(16, "stationary-fixture-1", 1)
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
			endpoint.report(payload, {"entities": meshes.size(), "updates": view_updates,
				"display": DisplayServer.get_name()})
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
	for entity_id in view.entities:
		if not meshes.has(entity_id):
			var mesh := MeshInstance3D.new()
			mesh.mesh = BoxMesh.new()
			mesh.scale = Vector3(0.8, 0.8, 0.8)
			var material := StandardMaterial3D.new()
			material.albedo_color = {"collector": Color.SEA_GREEN,
				"belt": Color.STEEL_BLUE, "processor": Color.GOLDENROD}[view.entities[entity_id].kind]
			mesh.material_override = material
			visual_root.add_child(mesh)
			meshes[entity_id] = mesh
		var cell: Array = view.entities[entity_id].cell
		meshes[entity_id].position = Vector3(cell[0], 0, cell[1])
	stock_label.text = actor + " | confirmed products: P=" + str(view.inventories.get("P", 0)) + " Q=" + str(view.inventories.get("Q", 0))

func _write(name_value: String, data: Dictionary):
	var file := FileAccess.open(artifact.path_join(name_value), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write owned probe evidence")
		quit(1)
		return
	file.store_string(JSON.stringify(data))
