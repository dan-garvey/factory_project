extends SceneTree
## Isolated loopback Session control with synthetic actor observations. No scene,
## ActorWorld, desktop input, or human gameplay is exercised.
## Run three headless processes against an imported project and the current
## native extension: use roles server, P and Q with the same empty owned
## --directory and --port; start clients after the server-ready marker. Require
## all three exit statuses and PASS markers. Then start server-resume, resume-P
## and resume-Q with the same directory and port, after the first server exits.
## Require all six processes to pass. Add --span-belt for a constructed
## mechanical span and its restored removal over the Session transport. Add
## --powered-span instead to exercise a native waterwheel-driven span.
## Add --reverse-belt to every process for
## generated-site reverse deposition and pickup after restart. The resumed Session uses the Store but
## does not exercise the ordinary server lifecycle or physical actor bodies.
const Session = preload("res://opening-session/session.gd")
const NativeModel = preload("res://opening/native_model.gd")
const Store = preload("res://save-tests/checkpoint_file.gd")
var session
var role := ""
var directory := ""
var port := 0
var replies := {}
var checks := 0
var failed := false
var reverse_belt := false
var span_belt := false
var powered_span := false
var serial := 0
var epoch := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
		elif arg.begins_with("--directory="): directory = arg.trim_prefix("--directory=")
		elif arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		elif arg == "--reverse-belt": reverse_belt = true
		elif arg == "--span-belt": span_belt = true
		elif arg == "--powered-span":
			span_belt = true
			powered_span = true
	call_deferred("run")

func verify(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error(message)

func finish_role() -> void:
	print("TILE_SESSION_%s %s %d" % ["FAIL" if failed else "PASS", role, checks])
	quit(1 if failed else 0)

func mark(name: String) -> void:
	var file := FileAccess.open(directory.path_join(name), FileAccess.WRITE)
	verify(file != null, "Open test marker " + name)
	if file != null:
		file.store_string("ok")
		file.close()

func until(predicate: Callable, message: String) -> bool:
	var deadline := Time.get_ticks_msec() + 20000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var ok: bool = predicate.call()
	verify(ok, message)
	return ok

func issue(action: Dictionary) -> Dictionary:
	var queued: Dictionary = session.submit(action)
	verify(queued.get("queued", false), "A client request must enter the Session transport")
	if not queued.get("queued", false): return {}
	var request: String = queued.request
	if not await until(func(): return replies.has(request), "The authority must answer " + request): return {}
	var result: Dictionary = replies[request]
	replies.erase(request)
	return result

func pose(x: float, z: float) -> bool:
	epoch += 1
	var result: Dictionary = session.world.publish_actor("P", [x, 1.0, z], epoch)
	if not result.get("accepted", false): push_error("Synthetic pose refused: " + str(result))
	return result.get("accepted", false)

func build(action: String, args: Dictionary) -> Dictionary:
	serial += 1
	var wire := {"context": session.context, "client": "P", "request": "reverse-build-" + str(serial), "action": action}
	wire.merge(args)
	var result: Dictionary = session.world.command(wire)
	if not result.get("accepted", false): push_error("Reverse route command refused: " + str(wire) + " " + str(result))
	return result

func build_reverse_route() -> bool:
	# This is the generated river route used by the independent native site
	# control. Positions are synthetic; commands still go through native Host.
	var hubs: Array[String] = []
	for entry in [["wheel", -2, "x"], ["collector", 0, "z"], ["belt", 1, "z"], ["processor", 2, "z"]]:
		if not pose(-1.65 if entry[0] == "wheel" else float(entry[1]) * 1.65, 3.3 if entry[0] == "wheel" else 0.0): return false
		var args := {"kind": entry[0], "cell": [entry[1], 1], "axis": entry[2]}
		if entry[0] == "wheel": args["level"] = 4
		var placed := build("place", args)
		if not placed.get("accepted", false): push_error("Place reverse machine: " + str(placed)); return false
		hubs.append(placed.entity)
	if not pose(-3.3, 0.0): return false
	for center in [[-12, 4, 4], [-12, 0, 4]]:
		if not build("place_gear", {"center": center, "axis": "x", "teeth": 2}).get("accepted", false): return false
	if not build("place_gear", {"center": [-16, 0, 4], "axis": "x", "teeth": 4}).get("accepted", false): return false
	if not pose(-3.3, 1.65): return false
	if not build("place_gear", {"center": [-12, 0, 8], "axis": "z", "teeth": 4}).get("accepted", false): return false
	for n in range(6):
		var x := n * 4 - 12
		if not pose(float(x) * 1.65 / 4.0, 3.3): return false
		var cog := build("place_gear", {"center": [x, 0, 12], "axis": "z", "teeth": 2})
		if not cog.get("accepted", false): return false
	for n in range(3):
		if not pose(float(n) * 1.65, 0.0): return false
		if not build("place_shaft", {"center": [n * 4, 0, 8], "axis": "z", "half_span": 2}).get("accepted", false): return false
	if not pose(-1.65, 0.0) or not build("set_power", {"active": true}).get("accepted", false): return false
	var motion: Dictionary = session.world.projection().motion[hubs[2]]
	if motion.state != "rotating" or motion.numerator <= 0:
		push_error("Reverse belt motion: " + str(motion))
		return false
	for turn in range(96):
		if not session.world.projection().dropped_material.is_empty(): break
		session.world.advance()
	return not session.world.projection().dropped_material.is_empty()

func run_reverse() -> void:
	var resumed := role.begins_with("resume-") or role == "server-resume"
	var save_path := directory.path_join("reverse.factory")
	if role in ["server", "server-resume"]:
		verify(session.serve_loopback(port, true, true, ["P", "Q"], true) == OK, "Start reverse-belt native Session")
		if failed: quit(1); return
		if resumed:
			verify(Store.read_into(session.world, save_path).get("accepted", false), "Restore the reverse-belt Store")
			session.context = session.world.context
		else:
			verify(build_reverse_route(), "Generated river route deposits a reversed blank")
		if failed: quit(1); return
		var snapshot: Dictionary = session.world.projection()
		verify(not snapshot.dropped_material.is_empty() and snapshot.stock.output == 0, "Reversed route has loose raw material and no output")
		if failed: quit(1); return
		var point: Array = snapshot.dropped_material[0].center
		verify(pose(float(point[0]) * 1.65 / 4.0, float(point[2]) * 1.65 / 4.0 - 1.65), "P can reach the reverse-end stack")
		verify(session.world.publish_actor("Q", [20.0, 1.0, 20.0], 1).get("accepted", false), "Synthetic Q observation is accepted")
		if failed: quit(1); return
		mark("resume-server-ready" if resumed else "server-ready")
		if not await until(func(): return FileAccess.file_exists(directory.path_join("resume-clients-done" if resumed else "clients-done")), "Clients finish reverse-belt phase"): quit(1); return
		if resumed:
			verify(session.world.projection().cargo.P.raw > 0, "The resumed authority records recovered raw cargo")
		else:
			verify(Store.write(session.world, save_path).get("accepted", false), "Store the generated reversed-belt state")
		if failed: quit(1); return
		mark("resume-server-done" if resumed else "server-done")
	else:
		var actor := role.trim_prefix("resume-") if resumed else role
		verify(session.join_loopback(port, actor) == OK, "Join reverse-belt Session")
		if not await until(func(): return session.is_ready(), "Receive reverse-belt projection"): quit(1); return
		mark(role + "-ready")
		if actor == "P":
			if not await until(func(): return FileAccess.file_exists(directory.path_join("resume-Q-ready" if resumed else "Q-ready")), "Q joins the reverse-belt phase"): quit(1); return
			var snapshot: Dictionary = session.projection()
			verify(not snapshot.dropped_material.is_empty() and snapshot.cargo.P.raw == 0, "P sees the loose stack and empty cargo")
			if failed: quit(1); return
			if resumed:
				var before: int = snapshot.dropped_material[0].raw
				var expected_drop: Dictionary = snapshot.dropped_material[0].duplicate(true)
				expected_drop.erase("center")
				var pickup := await issue({"action": "pickup_material", "center": snapshot.dropped_material[0].center, "expected": expected_drop})
				verify(pickup.get("accepted", false), "P collects the restored stack over Session: " + str(pickup))
				var request: String = pickup.get("request", "")
				verify(session.retry(request).get("queued", false), "Retry the pickup request")
				if await until(func(): return replies.has(request), "Retry receives the original receipt"):
					verify(replies[request].get("accepted", false) and replies[request].get("duplicate", false), "Pickup retry is deduplicated")
					replies.erase(request)
				verify(session.projection().cargo.P.raw == before, "Pickup transfers the stack once")
				verify(session.projection().dropped_material.is_empty(), "The recovered stack leaves the ground")
			if failed: quit(1); return
			mark("resume-P-done" if resumed else "P-done")
		else:
			var original: Dictionary = session.projection()
			if not await until(func(): return FileAccess.file_exists(directory.path_join("resume-P-done" if resumed else "P-done")), "P finishes the reverse-belt phase"): quit(1); return
			if resumed:
				if not await until(func(): return session.projection().get("cargo", {}).get("P", {}).get("raw", 0) > 0, "Q observes recovered cargo"): quit(1); return
				verify(not original.dropped_material.is_empty() and session.projection().cargo.P.raw == original.dropped_material[0].raw
					and session.projection().dropped_material.is_empty(), "Q sees the exact stack transfer and no remaining ground cargo")
			else:
				verify(not session.projection().dropped_material.is_empty(), "Q sees the reverse-end stack")
			if failed: quit(1); return
			mark("resume-clients-done" if resumed else "clients-done")
			if not await until(func(): return FileAccess.file_exists(directory.path_join("resume-server-done" if resumed else "server-done")), "Authority completes the reverse-belt phase"): quit(1); return
	print("REVERSE_BELT_SESSION_%s %s %d" % ["FAIL" if failed else "PASS", role, checks])
	quit(1 if failed else 0)

func run_span() -> void:
	var resumed := role.begins_with("resume-") or role == "server-resume"
	var prefix := "resume-" if resumed else ""
	var save_path := directory.path_join("span.factory")
	if role in ["server", "server-resume"]:
		verify(session.serve_loopback(port, true, true, ["P", "Q"], true) == OK, "Start the native span authority")
		if failed: quit(1); return
		var saved_hash := ""
		if resumed:
			saved_hash = FileAccess.get_sha256(save_path)
			verify(not saved_hash.is_empty() and Store.read_into(session.world, save_path).get("accepted", false), "A fresh authority restores the belt Store")
			session.context = session.world.context
		var p_pose := [0.0, 2.15, 3.3] if powered_span else [1.65, 1.0, -1.65]
		verify(session.world.publish_actor("P", p_pose, 1).get("accepted", false), "Synthetic P remains within reach")
		verify(session.world.publish_actor("Q", [20.0, 1.0, 20.0], 1).get("accepted", false), "Synthetic Q remains clear")
		if failed: quit(1); return
		mark(prefix + "server-ready")
		if not await until(func(): return FileAccess.file_exists(directory.path_join(prefix + "clients-done")), "Both span clients finish"): quit(1); return
		var state: Dictionary = session.world.projection()
		if resumed:
			verify(state.belt_spans.is_empty() and state.part_kits.P.belt == 1, "The restored belt is removed and refunded once")
			verify(FileAccess.get_sha256(save_path) == saved_hash, "Continuation leaves the saved bytes unchanged")
		else:
			verify(state.belt_spans.size() == 1 and state.part_kits.P.belt == 0, "The authority owns the constructed belt")
			verify(Store.write(session.world, save_path).get("accepted", false), "The Store writes the constructed span")
		if failed: quit(1); return
		mark(prefix + "server-done")
	else:
		var actor := role.trim_prefix("resume-") if resumed else role
		verify(session.join_loopback(port, actor) == OK, "Join the span authority")
		if not await until(func(): return session.is_ready(), "Receive the confirmed span projection"): quit(1); return
		mark(prefix + actor + "-ready")
		if actor == "P":
			if not await until(func(): return FileAccess.file_exists(directory.path_join(prefix + "Q-ready")), "Q joins before the span request"): quit(1); return
			if resumed:
				var restored: Dictionary = session.projection()
				verify(restored.belt_spans.size() == 1 and restored.part_kits.P.belt == 0, "P receives the exact saved belt custody")
				if failed: quit(1); return
				var id: String = str(restored.belt_spans.keys()[0])
				if powered_span:
					var saved_span: Dictionary = restored.belt_spans[id]
					verify(_span_powered(restored, saved_span), "P receives equal signed shaft rates after restore")
				var removed := await issue({"action": "remove_belt_span", "entity": id})
				verify(removed.get("accepted", false), "P removes the restored span through Session: " + str(removed))
			else:
				if powered_span:
					var wheel := await issue({"action": "place", "kind": "wheel", "cell": [-2, 1], "axis": "x", "level": 4})
					verify(wheel.get("accepted", false), "P constructs the native waterwheel: " + str(wheel))
					if failed: quit(1); return
				var first_center := [-4, 4, 4] if powered_span else [0, 0, 0]
				var last_center := [-4, 4, 12] if powered_span else [8, 0, 0]
				var axis := "x" if powered_span else "z"
				var first := await issue({"action": "place_shaft", "center": first_center, "axis": axis, "half_span": 2})
				var last := await issue({"action": "place_shaft", "center": last_center, "axis": axis, "half_span": 2})
				verify(first.get("accepted", false) and last.get("accepted", false), "P constructs both shaft tiles through Session")
				if failed: quit(1); return
				var span := await issue({"action": "place_belt_span", "from": first.entity, "to": last.entity})
				verify(span.get("accepted", false), "P constructs the belt through Session: " + str(span))
				if failed: quit(1); return
				var request: String = span.request
				verify(session.retry(request).get("queued", false), "The original belt request can be retried")
				if await until(func(): return replies.has(request), "The belt retry receives its receipt"):
					verify(replies[request].get("accepted", false) and replies[request].get("duplicate", false), "The belt retry spends no second item")
					replies.erase(request)
				if powered_span:
					var power := await issue({"action": "set_power", "active": true})
					verify(power.get("accepted", false), "P starts the native wheel: " + str(power))
			if failed: quit(1); return
			mark(prefix + "P-done")
		else:
			if not await until(func(): return FileAccess.file_exists(directory.path_join(prefix + "P-done")), "P completes the span request"): quit(1); return
			if not await until(func(): return session.projection().get("belt_spans", {}).size() == (0 if resumed else 1), "Q receives the confirmed belt change"): quit(1); return
			var view: Dictionary = session.projection()
			verify(view.transmission_parts.size() == 2 and view.part_kits.P.shaft == 6 and view.part_kits.P.belt == (1 if resumed else 0), "Q sees both shafts and the correct belt custody")
			if not resumed:
				var span: Dictionary = view.belt_spans.values()[0]
				verify(view.transmission_parts.has(span.from) and view.transmission_parts.has(span.to), "Q sees both actual belt endpoint identities")
				var belt_edge := false
				for edge in view.engagements:
					if edge.kind == 2 and ((edge.a == span.from and edge.b == span.to) or (edge.b == span.from and edge.a == span.to)):
						belt_edge = true
				verify(belt_edge, "Q observes the native belt transmission engagement")
				if powered_span:
					verify(_span_powered(view, span), "Q observes equal nonzero signed rates across the belt")
			else:
				verify(not view.engagements.any(func(edge: Dictionary): return edge.kind == 2), "Removing the span removes its belt transmission engagement")
				if powered_span:
					var driven := ""
					var disconnected := ""
					for id in view.transmission_parts:
						if view.transmission_parts[id].center == [-4, 4, 4]: driven = str(id)
						if view.transmission_parts[id].center == [-4, 4, 12]: disconnected = str(id)
					verify(not driven.is_empty() and not disconnected.is_empty() and view.motion[driven].state == "rotating"
						and view.motion[disconnected].state == "unpowered", "Q observes the far shaft stop while the source shaft remains driven")
			if failed: quit(1); return
			mark(prefix + "clients-done")
			if not await until(func(): return FileAccess.file_exists(directory.path_join(prefix + "server-done")), "The authority completes the span phase"): quit(1); return
	print("BELT_SPAN_SESSION_%s %s %d" % ["FAIL" if failed else "PASS", role, checks])
	quit(1 if failed else 0)

func _span_powered(view: Dictionary, span: Dictionary) -> bool:
	var first: Dictionary = view.motion.get(span.from, {})
	var last: Dictionary = view.motion.get(span.to, {})
	return first.get("state") == "rotating" and last.get("state") == "rotating" and first.get("numerator", 0) != 0 \
		and first.get("numerator") == last.get("numerator") and first.get("denominator") == last.get("denominator")

func run() -> void:
	if not directory.is_absolute_path() or not DirAccess.dir_exists_absolute(directory) or not role in ["server", "P", "Q", "server-resume", "resume-P", "resume-Q"]:
		push_error("Expected an owned directory and a server, P, or Q role")
		quit(1)
		return
	var container := Node.new()
	container.name = "OpeningShared"
	session = Session.new()
	session.name = "Session"
	container.add_child(session)
	root.add_child(container)
	session.outcome.connect(func(value: Dictionary): replies[value.request] = value)
	if reverse_belt:
		await run_reverse()
		return
	if span_belt:
		await run_span()
		return
	if role in ["server", "server-resume"]:
		verify(session.serve_loopback(port, true, true, ["P", "Q"], true) == OK, "The native loopback authority must start")
		if failed: quit(1); return
		var save_path := directory.path_join("worksite.factory")
		var input_hash := ""
		if role == "server-resume":
			input_hash = FileAccess.get_sha256(save_path)
			verify(not input_hash.is_empty(), "The original Store file exists")
			verify(Store.read_into(session.world, save_path).get("accepted", false), "A fresh Session authority loads the Store file")
			session.context = session.world.context
			verify(FileAccess.get_sha256(save_path) == input_hash, "Restoring preserves the original Store bytes")
			if failed: quit(1); return
		verify(session.world.publish_actor("P", [1.65, 1.0, -1.65], 1).get("accepted", false), "Synthetic P observation is accepted")
		verify(session.world.publish_actor("Q", [20.0, 1.0, 20.0], 1).get("accepted", false), "Synthetic Q observation is accepted")
		if failed: quit(1); return
		if role == "server-resume":
			mark("resume-server-ready")
			if not await until(func(): return FileAccess.file_exists(directory.path_join("resume-clients-done")), "Both resumed clients must finish"): quit(1); return
			verify(session.world.projection().transmission_parts.size() == 1, "The resumed authority retains the shaft after cog removal")
			verify(FileAccess.get_sha256(save_path) == input_hash, "Continued work does not modify the original save")
			if failed: quit(1); return
			mark("resume-server-done")
			finish_role()
			return
		mark("server-ready")
		if not await until(func(): return FileAccess.file_exists(directory.path_join("clients-done")), "Both clients must finish"): quit(1); return
		var saved: Dictionary = session.world.checkpoint()
		var fresh = NativeModel.new(session.context, ["P", "Q"])
		verify(fresh.boot_result.get("accepted", false), "A fresh native Host initializes")
		verify(fresh.restore_checkpoint(saved).get("accepted", false), "The authority checkpoint restores into a fresh Host")
		verify(fresh.checkpoint() == saved, "The restored checkpoint preserves geometry, custody, and request history")
		verify(Store.write(session.world, save_path).get("accepted", false), "The existing Store validates and publishes the native checkpoint")
		if failed: quit(1); return
		mark("server-done")
	else:
		var resumed := role.begins_with("resume-")
		var actor := role.trim_prefix("resume-") if resumed else role
		verify(session.join_loopback(port, actor) == OK, "Client connects to loopback authority")
		if not await until(func(): return session.is_ready(), "Client receives its authenticated welcome"): quit(1); return
		mark(role + "-ready")
		if resumed:
			if actor == "P":
				if not await until(func(): return FileAccess.file_exists(directory.path_join("resume-Q-ready")), "Q joins the restored Session"): quit(1); return
				var old_namespace := FileAccess.get_file_as_string(directory.path_join("P-namespace"))
				verify(not old_namespace.is_empty() and session.request_namespace != old_namespace,
					"The resumed client receives a fresh request namespace")
				var snapshot: Dictionary = session.projection()
				verify(snapshot.transmission_parts.size() == 2 and snapshot.part_kits.P.shaft == 7 and snapshot.part_kits.P.gear == 9, "P receives the restored parts and custody")
				var cog_id := ""
				for id in snapshot.transmission_parts:
					if snapshot.transmission_parts[id].kind == "gear": cog_id = str(id)
				verify(not cog_id.is_empty(), "The saved cog keeps a usable identity")
				if failed: quit(1); return
				var removed: Dictionary = await issue({"action": "remove", "entity": cog_id})
				verify(removed.get("accepted", false), "P removes the restored cog through the resumed Session: " + str(removed.get("reason", "")))
				if failed: quit(1); return
				mark("resume-P-done")
			else:
				if not await until(func(): return FileAccess.file_exists(directory.path_join("resume-P-done")), "P completes continued work"): quit(1); return
				if not await until(func(): return session.projection().get("transmission_parts", {}).size() == 1, "Q observes the resumed removal"): quit(1); return
				var resumed_view: Dictionary = session.projection()
				verify(resumed_view.part_kits.P.shaft == 7 and resumed_view.part_kits.P.gear == 10, "Q observes the actual cog refund")
				if failed: quit(1); return
				mark("resume-clients-done")
				if not await until(func(): return FileAccess.file_exists(directory.path_join("resume-server-done")), "The resumed authority verifies continuation"): quit(1); return
			finish_role()
			return
		if role == "P":
			if not await until(func(): return FileAccess.file_exists(directory.path_join("Q-ready")), "Q joins before construction"): quit(1); return
			var namespace_file := FileAccess.open(directory.path_join("P-namespace"), FileAccess.WRITE)
			verify(namespace_file != null, "The initial request namespace is retained for comparison")
			if namespace_file != null:
				namespace_file.store_string(session.request_namespace)
				namespace_file.close()
			if failed: quit(1); return
			var shaft: Dictionary = await issue({"action": "place_shaft", "center": [0, 0, 0], "axis": "x", "half_span": 2})
			verify(shaft.get("accepted", false), "P places a one-tile shaft: " + str(shaft.get("reason", "")))
			var request: String = shaft.get("request", "")
			var duplicate: Dictionary = session.retry(request)
			verify(duplicate.get("queued", false), "P retries the original shaft request")
			if await until(func(): return replies.has(request), "Retry receives its cached outcome"):
				verify(replies[request].get("accepted", false) and replies[request].get("duplicate", false), "Retry must not spend a second shaft")
				replies.erase(request)
			var cog: Dictionary = await issue({"action": "place_gear", "center": [4, 0, 0], "axis": "x", "teeth": 2})
			verify(cog.get("accepted", false), "P places an adjacent tile cog: " + str(cog.get("reason", "")))
			var invalid: Dictionary = await issue({"action": "place_gear", "center": [5, 0, 0], "axis": "x", "teeth": 2})
			verify(not invalid.get("accepted", true) and invalid.get("reason") == "invalid_cell",
				"The authority rejects an off-grid cog over the real wire")
			if failed: quit(1); return
			mark("P-done")
		else:
			if not await until(func(): return FileAccess.file_exists(directory.path_join("P-done")), "P completes the command sequence"): quit(1); return
			if not await until(func(): return session.projection().get("transmission_parts", {}).size() == 2, "Q observes both confirmed parts"): quit(1); return
			var view: Dictionary = session.projection()
			var centers := []
			for part in view.transmission_parts.values(): centers.append(part.center)
			verify([0, 0, 0] in centers and [4, 0, 0] in centers, "Q sees the same distinct tile centers")
			verify(view.part_kits.P.shaft == 7 and view.part_kits.P.gear == 9, "Q sees one shaft and one cog debited")
			var connected := false
			for edge in view.engagements:
				if edge.kind == 1 and view.transmission_parts.has(edge.a) and view.transmission_parts.has(edge.b):
					connected = true
			verify(connected, "Q observes the confirmed shaft-to-cog axle engagement")
			if failed: quit(1); return
			mark("clients-done")
			if not await until(func(): return FileAccess.file_exists(directory.path_join("server-done")), "Server verifies fresh-Host restore"): quit(1); return
	finish_role()
