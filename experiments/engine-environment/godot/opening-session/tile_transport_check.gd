extends SceneTree
## Isolated loopback Session control with synthetic actor observations. No scene,
## ActorWorld, desktop input, or human gameplay is exercised.
## Run three headless processes against an imported project and the current
## native extension: use roles server, P and Q with the same empty owned
## --directory and --port; start clients after the server-ready marker. Require
## all three exit statuses and PASS markers. Then start server-resume, resume-P
## and resume-Q with the same directory and port, after the first server exits.
## Require all six processes to pass.
## The default native arrival route harvests two finite timber units, crafts
## two shaft kits at the pod, and builds, restores and reclaims those parts.
## All actor positions in this fixture are synthetic trusted observations.
## Add --span-belt for a constructed
## mechanical span and its restored removal over the Session transport. Add
## --powered-span instead to exercise a native waterwheel-driven span, or
## --inclined-span to construct its elevated 45-degree counterpart. Add
## --reverse-endpoints to submit either span in the opposite endpoint order.
## Add --middle-pulley to --powered-span to insert and restore a driven pulley.
## Add --cog-train to exercise a powered large/small pair and its restore.
## Add --overload to exercise speed-weighted load and recovery across restart.
## Add --fractional-press to exercise workpiece recovery and continuation.
## Add --reverse-belt to every process for
## generated-site reverse backpressure and recovery after restart. Add --belt-loading
## to exercise actual carried stock loaded over Session and restored via Store.
## The resumed Session uses the Store but
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
var inclined_span := false
var reverse_endpoints := false
var middle_pulley := false
var cog_train := false
var overload := false
var fractional_press := false
var belt_loading := false
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
		elif arg == "--inclined-span":
			span_belt = true
			powered_span = true
			inclined_span = true
		elif arg == "--reverse-endpoints": reverse_endpoints = true
		elif arg == "--middle-pulley": middle_pulley = true
		elif arg == "--cog-train": cog_train = true
		elif arg == "--overload": overload = true
		elif arg == "--fractional-press": fractional_press = true
		elif arg == "--belt-loading": belt_loading = true
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

func build_reverse_route(for_loading: bool = false) -> bool:
	# This is the generated river route used by the independent native site
	# control. Positions are synthetic; commands still go through native Host.
	if not pose(0.0, 0.0): return false
	if not build("place_foundation", {"cell": [0, 1], "level": 4}).get("accepted", false): return false
	if not pose(4.95, 0.0) or not build("place_foundation", {"cell": [3, 1], "level": 4}).get("accepted", false): return false
	for entry in [["wheel", -2, "x"], ["collector", 0, "z"], ["processor", 3, "z"]]:
		if not pose(-1.65 if entry[0] == "wheel" else float(entry[1]) * 1.65, 3.3 if entry[0] == "wheel" else 0.0): return false
		var args := {"kind": entry[0], "cell": [entry[1], 1], "axis": entry[2], "level": 4}
		var placed := build("place", args)
		if not placed.get("accepted", false): push_error("Place reverse machine: " + str(placed)); return false
	if not pose(-3.3, 0.0): return false
	if not build("place_gear", {"center": [-4, 4, 4], "axis": "x", "teeth": 4}).get("accepted", false): return false
	if not pose(-3.3, 1.65): return false
	if not build("place_gear", {"center": [0, 4, 8], "axis": "z", "teeth": 4}).get("accepted", false): return false
	for n in range(2):
		var x := n * 4
		if not pose(float(x) * 1.65 / 4.0, 3.3): return false
		var cog := build("place_gear", {"center": [x, 4, 12], "axis": "z", "teeth": 2})
		if not cog.get("accepted", false): return false
	if not pose(1.65, 0.0): return false
	if not build("place_shaft", {"center": [4, 4, 8], "axis": "z", "half_span": 2}).get("accepted", false): return false
	var endpoints: Array[String] = []
	for n in range(1, 3):
		if not pose(float(n) * 1.65, 0.0): return false
		var placed := build("place_shaft", {"center": [n * 4, 4, 4], "axis": "z", "half_span": 2})
		if not placed.get("accepted", false): return false
		endpoints.append(placed.entity)
	if not pose(2.475, 0.0): return false
	if not build("place_belt_span", {"from": endpoints[0], "to": endpoints[1]}).get("accepted", false): return false
	if not pose(-1.65, 0.0): return false
	var motion: Dictionary = session.world.projection().motion[endpoints[0]]
	if motion.state != "rotating" or motion.numerator <= 0:
		push_error("Reverse belt motion: " + str(motion))
		return false
	for turn in range(96):
		if for_loading and session.world.projection().stock.collector > 0: return true
		var view: Dictionary = session.world.projection()
		var slots: Array = view.belt_spans.values()[0].slots
		if not for_loading and slots[0] is Dictionary and slots[0].get("raw") == 1:
			for blocked_turn in range(16): session.world.advance()
			view = session.world.projection()
			return view.belt_spans.values()[0].slots[0] is Dictionary \
				and view.belt_spans.values()[0].slots[0].get("raw") == 1 \
				and view.dropped_material.is_empty()
		session.world.advance()
	return false

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
			verify(build_reverse_route(), "Generated river route blocks a reversed blank against the collector")
		if failed: quit(1); return
		var snapshot: Dictionary = session.world.projection()
		verify(snapshot.dropped_material.is_empty() and snapshot.stock.output == 0, "The blocked reverse route has no loose item or output")
		verify(snapshot.belt_spans.size() == 1 and snapshot.part_kits.P.belt == 1,
			"The route uses one carried shaft-driven belt span")
		if not snapshot.belt_spans.is_empty():
			var span: Dictionary = snapshot.belt_spans.values()[0]
			verify(_span_powered(snapshot, span) and snapshot.motion[span.from].numerator > 0,
				"The reverse span connects matching positively rotating shafts")
			verify(span.slots[0] is Dictionary and span.slots[0].get("raw") == 1, "The collector-facing end retains the blocked blank")
		if failed: quit(1); return
		verify(pose(0.0, 0.0), "P can reach the collector-facing belt slot")
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
			var span_id := str(snapshot.belt_spans.keys()[0])
			var blocked: Variant = snapshot.belt_spans[span_id].slots[0]
			verify(blocked is Dictionary and blocked.get("raw") == 1 and snapshot.cargo.P.raw == 0, "P sees the blocked blank and empty cargo")
			if failed: quit(1); return
			if resumed:
				var pickup := await issue({"action": "recover_belt_slot", "entity": span_id, "slot": 0, "expected": blocked.duplicate(true)})
				verify(pickup.get("accepted", false), "P recovers the restored blocked blank over Session")
				var request: String = pickup.get("request", "")
				verify(session.retry(request).get("queued", false), "Retry the belt recovery")
				if await until(func(): return replies.has(request), "Retry receives the original receipt"):
					verify(replies[request].get("accepted", false) and replies[request].get("duplicate", false), "Recovery retry is deduplicated")
					replies.erase(request)
				verify(session.projection().cargo.P.raw == 1 and session.projection().belt_spans[span_id].slots[0] == null,
					"Recovery moves the blocked blank once")
			if failed: quit(1); return
			mark("resume-P-done" if resumed else "P-done")
		else:
			var original: Dictionary = session.projection()
			if not await until(func(): return FileAccess.file_exists(directory.path_join("resume-P-done" if resumed else "P-done")), "P finishes the reverse-belt phase"): quit(1); return
			if resumed:
				if not await until(func(): return session.projection().get("cargo", {}).get("P", {}).get("raw", 0) > 0, "Q observes recovered cargo"): quit(1); return
				var original_span: Dictionary = original.belt_spans.values()[0]
				var confirmed: Dictionary = session.projection()
				verify(original_span.slots[0].raw == 1 and confirmed.cargo.P.raw == 1 and confirmed.belt_spans.values()[0].slots[0] == null,
					"Q sees the exact blocked-blank transfer")
			else:
				verify(session.projection().belt_spans.values()[0].slots[0].get("raw") == 1, "Q sees the blocked end slot")
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
			verify(state.belt_spans.is_empty() and state.part_kits.P.belt == 2, "The restored belt is removed and refunded once")
			verify(FileAccess.get_sha256(save_path) == saved_hash, "Continuation leaves the saved bytes unchanged")
		else:
			verify(state.belt_spans.size() == 1 and state.part_kits.P.belt == 1, "The authority owns the constructed belt")
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
				verify(restored.belt_spans.size() == 1 and restored.part_kits.P.belt == 1, "P receives the exact saved belt custody")
				if failed: quit(1); return
				var id: String = str(restored.belt_spans.keys()[0])
				if powered_span:
					var saved_span: Dictionary = restored.belt_spans[id]
					verify(_span_powered(restored, saved_span), "P receives equal signed shaft rates after restore")
					if middle_pulley:
						var middle := _middle_id(restored)
						verify(not middle.is_empty() and _middle_powered(restored, saved_span), "The saved intermediate pulley remains driven")
						if failed: quit(1); return
						var removed_middle := await issue({"action": "remove", "entity": middle})
						verify(removed_middle.get("accepted", false), "P removes the restored pulley: " + str(removed_middle))
						verify(session.projection().belt_spans.size() == 1 and _span_powered(session.projection(), saved_span), "Removing the pulley preserves the powered belt")
						if failed: quit(1); return
						mark("pulley-removed")
						if not await until(func(): return FileAccess.file_exists(directory.path_join("pulley-observed")), "Q observes the remaining powered belt"): quit(1); return
				var removed := await issue({"action": "remove_belt_span", "entity": id})
				verify(removed.get("accepted", false), "P removes the restored span through Session: " + str(removed))
			else:
				if powered_span:
					var wheel := await issue({"action": "place", "kind": "wheel", "cell": [-2, 1], "axis": "x", "level": 4})
					verify(wheel.get("accepted", false), "P constructs the native waterwheel: " + str(wheel))
					if failed: quit(1); return
				var first_center := [-4, 4, 4] if powered_span else [0, 4, 0]
				var last_center := ([-4, 8, 8] if inclined_span else [-4, 4, 12]) if powered_span else [8, 4, 0]
				var axis := "x" if powered_span else "z"
				var first := await issue({"action": "place_shaft", "center": first_center, "axis": axis, "half_span": 2})
				var last := await issue({"action": "place_shaft", "center": last_center, "axis": axis, "half_span": 2})
				verify(first.get("accepted", false) and last.get("accepted", false), "P constructs both shaft tiles through Session")
				if failed: quit(1); return
				var from: String = last.entity if reverse_endpoints else first.entity
				var selection := await issue({"action": "select_belt_shaft", "entity": from})
				verify(selection.get("accepted", false), "P selects the first shaft through Session: " + str(selection))
				if failed: quit(1); return
				var span := await issue({"action": "place_selected_belt_span", "from": from,
					"to": first.entity if reverse_endpoints else last.entity, "selection": selection.request})
				verify(span.get("accepted", false), "P constructs the belt through Session: " + str(span))
				if failed: quit(1); return
				var request: String = span.request
				verify(session.retry(request).get("queued", false), "The original belt request can be retried")
				if await until(func(): return replies.has(request), "The belt retry receives its receipt"):
					verify(replies[request].get("accepted", false) and replies[request].get("duplicate", false), "The belt retry spends no second item")
					replies.erase(request)
				if powered_span:
					if middle_pulley:
						var middle := await issue({"action": "place_shaft", "center": [-4, 4, 8], "axis": "x", "half_span": 2})
						verify(middle.get("accepted", false), "P inserts a pulley into the powered span: " + str(middle))
			if failed: quit(1); return
			mark(prefix + "P-done")
		else:
			if resumed and middle_pulley:
				if not await until(func(): return FileAccess.file_exists(directory.path_join("pulley-removed")), "P removes the restored pulley"): quit(1); return
				if not await until(func(): return session.projection().get("transmission_parts", {}).size() == 2, "Q receives the pulley removal"): quit(1); return
				var remaining: Dictionary = session.projection()
				verify(remaining.belt_spans.size() == 1 and remaining.part_kits.P.shaft == 6 and _span_powered(remaining, remaining.belt_spans.values()[0]), "Q sees the refund and both endpoints still powered")
				if failed: quit(1); return
				mark("pulley-observed")
			if not await until(func(): return FileAccess.file_exists(directory.path_join(prefix + "P-done")), "P completes the span request"): quit(1); return
			if not await until(func(): return session.projection().get("belt_spans", {}).size() == (0 if resumed else 1), "Q receives the confirmed belt change"): quit(1); return
			var view: Dictionary = session.projection()
			var shaft_count := 3 if middle_pulley and not resumed else 2
			verify(view.transmission_parts.size() == shaft_count and view.part_kits.P.shaft == 8 - shaft_count and view.part_kits.P.belt == (2 if resumed else 1), "Q sees the shafts and correct belt custody")
			if not resumed:
				var span: Dictionary = view.belt_spans.values()[0]
				verify(view.transmission_parts.has(span.from) and view.transmission_parts.has(span.to), "Q sees both actual belt endpoint identities")
				var belt_edges: Array = []
				for edge in view.engagements:
					if edge.kind == 2: belt_edges.append(edge)
				if middle_pulley:
					var middle := _middle_id(view)
					verify(belt_edges.size() == 2 and belt_edges.all(func(edge: Dictionary): return edge.a == middle or edge.b == middle), "Q observes both belt engagements through the intermediate pulley")
				else:
					verify(belt_edges.size() == 1 and ((belt_edges[0].a == span.from and belt_edges[0].b == span.to) or (belt_edges[0].b == span.from and belt_edges[0].a == span.to)), "Q observes the native belt transmission engagement")
				if powered_span:
					verify(_span_powered(view, span), "Q observes equal nonzero signed rates across the belt")
					if middle_pulley:
						verify(_middle_powered(view, span), "Q observes the inserted pulley at the same signed rate")
			else:
				verify(not view.engagements.any(func(edge: Dictionary): return edge.kind == 2), "Removing the span removes its belt transmission engagement")
				if powered_span:
					var driven := ""
					var disconnected := ""
					for id in view.transmission_parts:
						if view.transmission_parts[id].center == [-4, 4, 4]: driven = str(id)
						if view.transmission_parts[id].center == ([-4, 8, 8] if inclined_span else [-4, 4, 12]): disconnected = str(id)
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

func _middle_id(view: Dictionary) -> String:
	for id in view.transmission_parts:
		if view.transmission_parts[id].center == [-4, 4, 8]: return str(id)
	return ""

func _middle_powered(view: Dictionary, span: Dictionary) -> bool:
	var middle := _middle_id(view)
	if middle.is_empty(): return false
	var source: Dictionary = view.motion.get(span.from, {})
	var motion: Dictionary = view.motion.get(middle, {})
	return motion.get("state") == "rotating" and motion.get("numerator") == source.get("numerator") \
		and motion.get("denominator") == source.get("denominator")

func _cog_at(view: Dictionary, center: Array) -> String:
	for id in view.transmission_parts:
		if view.transmission_parts[id].get("kind") == "gear" and view.transmission_parts[id].get("center") == center:
			return str(id)
	return ""

func _cog_ratio(view: Dictionary) -> bool:
	var large := _cog_at(view, [-4, 4, 4])
	var small := _cog_at(view, [-4, 8, 8])
	if large.is_empty() or small.is_empty(): return false
	var large_part: Dictionary = view.transmission_parts[large]
	var small_part: Dictionary = view.transmission_parts[small]
	if large_part.get("axis") != 0 or small_part.get("axis") != 0 \
		or large_part.get("teeth") != 4 or small_part.get("teeth") != 2: return false
	var meshed := false
	for edge in view.engagements:
		if edge.kind == 0 and ((edge.a == large and edge.b == small) or (edge.a == small and edge.b == large)):
			meshed = true
	if not meshed: return false
	var a: Dictionary = view.motion.get(large, {})
	var b: Dictionary = view.motion.get(small, {})
	if a.get("state") != "rotating" or b.get("state") != "rotating": return false
	var an: int = a.get("numerator", 0)
	var ad: int = a.get("denominator", 0)
	var bn: int = b.get("numerator", 0)
	var bd: int = b.get("denominator", 0)
	return an != 0 and ad > 0 and bd > 0 and bn * ad == -2 * an * bd

func run_cog_train() -> void:
	var resumed := role.begins_with("resume-") or role == "server-resume"
	var prefix := "resume-" if resumed else ""
	var save_path := directory.path_join("cog-train.factory")
	if role in ["server", "server-resume"]:
		verify(session.serve_loopback(port, true, true, ["P", "Q"], true) == OK, "Start the cog authority")
		if failed: quit(1); return
		var saved_hash := ""
		if resumed:
			saved_hash = FileAccess.get_sha256(save_path)
			verify(not saved_hash.is_empty() and Store.read_into(session.world, save_path).get("accepted", false), "Restore the cog train into a fresh authority")
			session.context = session.world.context
		verify(session.world.publish_actor("P", [0.0, 2.15, 3.3], 1).get("accepted", false), "Synthetic P can reach the train")
		verify(session.world.publish_actor("Q", [20.0, 1.0, 20.0], 1).get("accepted", false), "Synthetic Q remains clear")
		if failed: quit(1); return
		mark(prefix + "server-ready")
		if not await until(func(): return FileAccess.file_exists(directory.path_join(prefix + "clients-done")), "Cog clients finish"): quit(1); return
		var state: Dictionary = session.world.projection()
		if resumed:
			verify(_cog_at(state, [-4, 8, 8]).is_empty() and state.part_kits.P.gear == 9, "Authority retains the large cog and refunds the small cog")
			verify(FileAccess.get_sha256(save_path) == saved_hash, "Continuation leaves the saved cog train unchanged")
		else:
			verify(_cog_ratio(state) and state.part_kits.P.gear == 8, "Authority retains the driven ratio and exact custody")
			verify(Store.write(session.world, save_path).get("accepted", false), "Store the powered cog train")
		if failed: quit(1); return
		mark(prefix + "server-done")
	else:
		var actor := role.trim_prefix("resume-") if resumed else role
		verify(session.join_loopback(port, actor) == OK, "Join the cog authority")
		if not await until(func(): return session.is_ready(), "Receive the cog projection"): quit(1); return
		mark(prefix + actor + "-ready")
		if actor == "P":
			if not await until(func(): return FileAccess.file_exists(directory.path_join(prefix + "Q-ready")), "Q joins before cog commands"): quit(1); return
			if resumed:
				var restored: Dictionary = session.projection()
				verify(_cog_ratio(restored) and restored.part_kits.P.gear == 8, "P sees the restored speed ratio and custody")
				if failed: quit(1); return
				var removed := await issue({"action": "remove", "entity": _cog_at(restored, [-4, 8, 8])})
				verify(removed.get("accepted", false), "P removes the restored small cog: " + str(removed))
			else:
				var wheel := await issue({"action": "place", "kind": "wheel", "cell": [-2, 1], "axis": "x", "level": 4})
				verify(wheel.get("accepted", false), "P constructs the waterwheel: " + str(wheel))
				var large := await issue({"action": "place_gear", "center": [-4, 4, 4], "axis": "x", "teeth": 4})
				var small := await issue({"action": "place_gear", "center": [-4, 8, 8], "axis": "x", "teeth": 2})
				verify(large.get("accepted", false) and small.get("accepted", false), "P places the diagonal cog pair: " + str([large, small]))
				if failed: quit(1); return
				verify(_cog_ratio(session.projection()), "P sees the automatic train and its signed ratio")
			if failed: quit(1); return
			mark(prefix + "P-done")
		else:
			if not await until(func(): return FileAccess.file_exists(directory.path_join(prefix + "P-done")), "P completes the cog commands"): quit(1); return
			if not await until(func(): return session.projection().get("transmission_parts", {}).size() == (1 if resumed else 2), "Q sees the cog graph"): quit(1); return
			var view: Dictionary = session.projection()
			if resumed:
				var large := _cog_at(view, [-4, 4, 4])
				verify(not large.is_empty() and view.motion[large].state == "rotating" and view.part_kits.P.gear == 9, "Q sees the remaining powered large cog and refund")
			else:
				verify(_cog_ratio(view) and view.part_kits.P.gear == 8, "Q sees the exact driven ratio and finite custody")
			if failed: quit(1); return
			mark(prefix + "clients-done")
			if not await until(func(): return FileAccess.file_exists(directory.path_join(prefix + "server-done")), "Cog authority finishes"): quit(1); return
	print("COG_TRAIN_SESSION_%s %s %d" % ["FAIL" if failed else "PASS", role, checks])
	quit(1 if failed else 0)

func _overload_motion(view: Dictionary, expect_overload: bool) -> bool:
	var cog := _cog_at(view, [0, 12, 12])
	if cog.is_empty(): return false
	var motion: Dictionary = view.motion.get(cog, {})
	var capacity: float = motion.get("capacity", 0.0)
	var impact: float = motion.get("impact", 0.0)
	return capacity > 0.0 and motion.get("overloaded", false) == expect_overload \
		and motion.get("state") == ("stalled" if expect_overload else "rotating") \
		and is_equal_approx(impact / capacity, 1.125 if expect_overload else 1.0)

func run_overload() -> void:
	var resumed := role.begins_with("resume-") or role == "server-resume"
	var prefix := "resume-" if resumed else ""
	var save_path := directory.path_join("overload.factory")
	if role in ["server", "server-resume"]:
		verify(session.serve_loopback(port, true, true, ["P", "Q"], true) == OK, "Start the overload authority")
		if failed: quit(1); return
		var saved_hash := ""
		if resumed:
			saved_hash = FileAccess.get_sha256(save_path)
			verify(not saved_hash.is_empty() and Store.read_into(session.world, save_path).get("accepted", false), "Restore the overloaded Store")
			session.context = session.world.context
		verify(session.world.publish_actor("P", [0.0, 2.15, 3.3], 1).get("accepted", false), "Publish synthetic P")
		verify(session.world.publish_actor("Q", [20.0, 1.0, 20.0], 1).get("accepted", false), "Publish synthetic Q")
		if failed: quit(1); return
		mark(prefix + "server-ready")
		if not resumed:
			if not await until(func(): return FileAccess.file_exists(directory.path_join("move-P")), "P requests a synthetic observation change"): quit(1); return
			verify(session.world.publish_actor("P", [0.0, 3.5, 3.3], 2).get("accepted", false), "Move synthetic P within reach")
			mark("P-moved")
		if not await until(func(): return FileAccess.file_exists(directory.path_join(prefix + "clients-done")), "Both overload clients finish"): quit(1); return
		var state: Dictionary = session.world.projection()
		verify(_overload_motion(state, not resumed), "Authority sees the expected overload or recovered rotation: " + str(state.motion))
		if resumed:
			verify(FileAccess.get_sha256(save_path) == saved_hash, "Recovery leaves the original save unchanged")
		else:
			verify(Store.write(session.world, save_path).get("accepted", false), "Store the overloaded network")
		if failed: quit(1); return
		mark(prefix + "server-done")
	else:
		var actor := role.trim_prefix("resume-") if resumed else role
		verify(session.join_loopback(port, actor) == OK, "Join the overload authority")
		if not await until(func(): return session.is_ready(), "Receive the overload projection"): quit(1); return
		mark(prefix + actor + "-ready")
		if actor == "P":
			if not await until(func(): return FileAccess.file_exists(directory.path_join(prefix + "Q-ready")), "Q joins before overload commands"): quit(1); return
			if resumed:
				var restored: Dictionary = session.projection()
				verify(_overload_motion(restored, true), "P sees restored overload")
				var collector := ""
				for id in restored.entities:
					if restored.entities[id].get("kind") == "collector": collector = str(id)
				verify(not collector.is_empty(), "The collector survives restore")
				if failed: quit(1); return
				var removed := await issue({"action": "remove", "entity": collector})
				verify(removed.get("accepted", false) and _overload_motion(session.projection(), false), "Removing collector load restores rotation: " + str(removed))
			else:
				var wheel := await issue({"action": "place", "kind": "wheel", "cell": [-2, 1], "axis": "x", "level": 4})
				verify(wheel.get("accepted", false), "Build the source wheel: " + str(wheel))
				for spec in [[[-4, 4, 4], 4], [[-4, 8, 8], 2], [[0, 8, 8], 4], [[0, 12, 12], 2]]:
					var placed := await issue({"action": "place_gear", "center": spec[0], "axis": "x", "teeth": spec[1]})
					verify(placed.get("accepted", false), "Build geared overload: " + str(placed))
					if failed: quit(1); return
				verify(_overload_motion(session.projection(), false), "The unloaded source rotates automatically")
				if failed: quit(1); return
				mark("move-P")
				if not await until(func(): return FileAccess.file_exists(directory.path_join("P-moved")), "Authority moves synthetic P"): quit(1); return
				for support in [[[0, 1], 4], [[1, 3], 12]]:
					var foundation := await issue({"action": "place_foundation", "cell": support[0], "level": support[1]})
					verify(foundation.get("accepted", false), "Build machine support: " + str(foundation))
					if failed: quit(1); return
				for spec in [["collector", [0, 1], 4], ["processor", [1, 3], 12]]:
					var machine := await issue({"action": "place", "kind": spec[0], "cell": spec[1], "axis": "x", "level": spec[2]})
					verify(machine.get("accepted", false), "Build driven machine: " + str(machine))
					if failed: quit(1); return
				var projected: Dictionary = session.projection()
				verify(_overload_motion(projected, true), "P sees overload after connecting both machines: " + str(projected.motion))
			if failed: quit(1); return
			mark(prefix + "P-done")
		else:
			if not await until(func(): return FileAccess.file_exists(directory.path_join(prefix + "P-done")), "P completes overload commands"): quit(1); return
			if not await until(func(): return _overload_motion(session.projection(), not resumed), "Q observes the expected load state"): quit(1); return
			mark(prefix + "clients-done")
			if not await until(func(): return FileAccess.file_exists(directory.path_join(prefix + "server-done")), "Authority finishes overload phase"): quit(1); return
	print("OVERLOAD_SESSION_%s %s %d" % ["FAIL" if failed else "PASS", role, checks])
	quit(1 if failed else 0)

func prepare_fractional_press() -> bool:
	if not pose(-1.65, 3.3): return false
	if not build("place", {"kind": "wheel", "cell": [-2, 1], "axis": "x", "level": 4}).get("accepted", false): return false
	if not pose(0.0, 0.0): return false
	if not build("place_foundation", {"cell": [0, 1], "level": 4}).get("accepted", false): return false
	var collector := build("place", {"kind": "collector", "cell": [0, 1], "axis": "x", "level": 4})
	if not collector.get("accepted", false): return false
	if not pose(-3.3, 0.0): return false
	if not build("place_gear", {"center": [-4, 4, 4], "axis": "x", "teeth": 4}).get("accepted", false): return false
	if not pose(-3.3, 3.3): return false
	if not build("place_gear", {"center": [-4, 8, 8], "axis": "x", "teeth": 2}).get("accepted", false): return false
	if not pose(1.65, 3.3): return false
	if not build("place_foundation", {"cell": [0, 2], "level": 8}).get("accepted", false): return false
	var press := build("place", {"kind": "processor", "cell": [0, 2], "axis": "x", "level": 8})
	if not press.get("accepted", false): return false
	if not pose(-1.65, 0.0): return false
	var rate: Dictionary = session.world.projection().motion[press.entity]
	if rate.state != "rotating" or abs(int(rate.numerator)) * 75 != 8 * int(rate.denominator):
		push_error("Expected an eight-seventy-fifths press rate: " + str(rate))
		return false
	for turn in range(32):
		if session.world.projection().stock.collector > 0: break
		session.world.advance()
	if not pose(0.0, 0.0): return false
	if not build("recover", {"entity": collector.entity}).get("accepted", false): return false
	if not pose(1.65, 3.3): return false
	if not build("insert_raw", {"entity": press.entity, "amount": 1}).get("accepted", false): return false
	session.world.advance() # Starts the original workpiece.
	session.world.advance() # Retains eight-seventy-fifths of a baseline work tick.
	var saved: Dictionary = session.world.checkpoint()
	var work: Variant = saved.get("world", {}).get("state", {}).get("material", {}).get("processing")
	return work is Dictionary and work.get("remaining_ticks") == 2 and work.get("completed_subticks") == 436 \
		and work.get("work_remainder") == 68 and work.get("work_remainder_denominator") == 75

func run_fractional_press() -> void:
	var resumed := role.begins_with("resume-") or role == "server-resume"
	var prefix := "resume-" if resumed else ""
	var save_path := directory.path_join("fractional-press.factory")
	if role in ["server", "server-resume"]:
		verify(session.serve_loopback(port, true, true, ["P", "Q"], true) == OK, "Start fractional press authority")
		if failed: quit(1); return
		if resumed:
			verify(Store.read_into(session.world, save_path).get("accepted", false), "Restore fractional work and receipt")
			session.context = session.world.context
		else:
			verify(prepare_fractional_press(), "Build and run a genuinely powered fractional press")
		verify(session.world.publish_actor("P", [1.65, 1.0, 3.3], epoch + 1).get("accepted", false), "P is within press reach")
		verify(session.world.publish_actor("Q", [20.0, 1.0, 20.0], 1).get("accepted", false), "Q remains clear")
		if failed: quit(1); return
		mark(prefix + "server-ready")
		if resumed:
			if not await until(func(): return FileAccess.file_exists(directory.path_join("resume-insert-observed")), "Both clients see the reinserted work"): quit(1); return
			session.world.advance()
			session._broadcast(session._frame())
			mark("resume-work-advanced")
		if not await until(func(): return FileAccess.file_exists(directory.path_join(prefix + "clients-done")), "Both fractional-work clients finish"): quit(1); return
		if not resumed:
			verify(Store.write(session.world, save_path).get("accepted", false), "Store the recovered fractional work and receipt")
		if failed: quit(1); return
		mark(prefix + "server-done")
	else:
		var actor := role.trim_prefix("resume-") if resumed else role
		verify(session.join_loopback(port, actor) == OK, "Join fractional press authority")
		if not await until(func(): return session.is_ready(), "Receive fractional press projection"): quit(1); return
		mark(prefix + actor + "-ready")
		if actor == "P":
			if not await until(func(): return FileAccess.file_exists(directory.path_join(prefix + "Q-ready")), "Q joins before work transfer"): quit(1); return
			var view: Dictionary = session.projection()
			var press := ""
			for id in view.entities:
				if view.entities[id].get("kind") == "processor": press = str(id)
			verify(not press.is_empty(), "The projected press keeps its identity")
			if failed: quit(1); return
			if resumed:
				var lots: Array = view.cargo.P.work_lots
				verify(lots.size() == 1 and lots[0].work_remainder == 68 and lots[0].work_remainder_denominator == 75,
					"P receives the original carried fractional work after restart")
				if failed: quit(1); return
				var inserted := await issue({"action": "insert_work", "entity": press, "work_id": lots[0].id})
				verify(inserted.get("accepted", false), "P reinserts the original workpiece")
				if failed: quit(1); return
				mark("resume-inserted")
				if not await until(func(): return FileAccess.file_exists(directory.path_join("resume-work-advanced")), "Authority advances the restored work"): quit(1); return
			var recovered := await issue({"action": "recover", "entity": press})
			var receipt_lots: Array = recovered.get("moved_work", [])
			verify(recovered.get("accepted", false) and receipt_lots.size() == 1, "P recovers the actual partial work")
			if failed: quit(1); return
			var lot: Dictionary = receipt_lots[0]
			verify(lot.work_remainder == (61 if resumed else 68) and lot.work_remainder_denominator == 75
				and lot.completed_subticks == (873 if resumed else 436)
				and lot.remaining_ticks == 2, "Receipt retains the exact expected work fraction")
			var request: String = recovered.request
			verify(session.retry(request).get("queued", false), "Retry the fractional recovery")
			if await until(func(): return replies.has(request), "The retry receives a receipt"):
				verify(replies[request].get("duplicate", false) and replies[request].get("moved_work") == receipt_lots,
					"The retry preserves the same work without moving it twice")
				replies.erase(request)
			if failed: quit(1); return
			mark(prefix + "P-done")
		else:
			if resumed:
				if not await until(func(): return FileAccess.file_exists(directory.path_join("resume-inserted")), "P reinserts the workpiece"): quit(1); return
				if not await until(func(): return session.projection().get("cargo", {}).get("P", {}).get("work_lots", []).is_empty(), "Q observes the insertion"): quit(1); return
				mark("resume-insert-observed")
			if not await until(func(): return FileAccess.file_exists(directory.path_join(prefix + "P-done")), "P recovers fractional work"): quit(1); return
			if not await until(func(): return session.projection().get("cargo", {}).get("P", {}).get("work_lots", []).size() == 1, "Q observes the recovered work"): quit(1); return
			var lot: Dictionary = session.projection().cargo.P.work_lots[0]
			verify(lot.work_remainder == (61 if resumed else 68) and lot.work_remainder_denominator == 75,
				"Q observes the exact fractional work in P's custody")
			if failed: quit(1); return
			mark(prefix + "clients-done")
			if not await until(func(): return FileAccess.file_exists(directory.path_join(prefix + "server-done")), "Authority completes the fractional-work phase"): quit(1); return
	print("FRACTIONAL_PRESS_SESSION_%s %s %d" % ["FAIL" if failed else "PASS", role, checks])
	quit(1 if failed else 0)

func run_belt_loading() -> void:
	var resumed := role.begins_with("resume-") or role == "server-resume"
	var prefix := "resume-" if resumed else ""
	var save_path := directory.path_join("belt-loading.factory")
	if role in ["server", "server-resume"]:
		verify(session.serve_loopback(port, true, true, ["P", "Q"], true) == OK, "Start belt-loading authority")
		if failed: quit(1); return
		if resumed:
			verify(Store.read_into(session.world, save_path).get("accepted", false), "Restore loaded belt and receipt")
			session.context = session.world.context
		else:
			verify(build_reverse_route(true), "Construct a powered route with real collector stock")
			var view: Dictionary = session.world.projection()
			var collector := ""
			for id in view.entities:
				if view.entities[id].get("kind") == "collector": collector = str(id)
			verify(not collector.is_empty() and pose(0.0, 0.0), "Reach the operating collector")
			if not failed: verify(build("recover", {"entity": collector}).get("accepted", false), "Recover actual collector stock")
		verify(pose(0.0, 0.0), "P can reach the first belt position")
		verify(session.world.publish_actor("Q", [20.0, 1.0, 20.0], 1).get("accepted", false), "Q remains clear")
		if failed: quit(1); return
		mark(prefix + "server-ready")
		if not await until(func(): return FileAccess.file_exists(directory.path_join(prefix + "clients-done")), "Both loading clients finish"): quit(1); return
		if not resumed: verify(Store.write(session.world, save_path).get("accepted", false), "Store the loaded belt and receipt")
		if failed: quit(1); return
		mark(prefix + "server-done")
	else:
		var actor := role.trim_prefix("resume-") if resumed else role
		verify(session.join_loopback(port, actor) == OK, "Join belt-loading authority")
		if not await until(func(): return session.is_ready(), "Receive belt-loading projection"): quit(1); return
		mark(prefix + actor + "-ready")
		if actor == "P":
			if not await until(func(): return FileAccess.file_exists(directory.path_join(prefix + "Q-ready")), "Q joins before transfer"): quit(1); return
			var view: Dictionary = session.projection()
			var id := str(view.belt_spans.keys()[0])
			var slot: int = int(FileAccess.get_file_as_string(directory.path_join("loaded-slot"))) if resumed else view.belt_spans[id].slots.find(null)
			if resumed:
				var item: Dictionary = view.belt_spans[id].slots[slot]
				verify(item.raw == 1, "P sees the loaded blank after restart")
				var recovered := await issue({"action": "recover_belt_slot", "entity": id, "slot": slot, "expected": item})
				verify(recovered.get("accepted", false), "P recovers the restored loaded blank")
			else:
				verify(view.cargo.P.raw > 0 and slot >= 0, "P carries stock and a belt position is empty: " + str([view.cargo.P, view.belt_spans[id].slots]))
				if failed: quit(1); return
				var slot_file := FileAccess.open(directory.path_join("loaded-slot"), FileAccess.WRITE)
				verify(slot_file != null, "Retain the loaded slot for restart")
				if slot_file != null: slot_file.store_string(str(slot)); slot_file.close()
				var loaded := await issue({"action": "load_belt_slot", "entity": id, "slot": slot, "item": "raw", "work_id": 0})
				verify(loaded.get("accepted", false), "P loads the carried blank over Session")
				if failed: quit(1); return
				var request: String = loaded.request
				verify(session.retry(request).get("queued", false), "Retry the belt load")
				if await until(func(): return replies.has(request), "The load retry receives its receipt"):
					verify(replies[request].get("duplicate", false), "Retry does not duplicate the blank")
					replies.erase(request)
			if failed: quit(1); return
			mark(prefix + "P-done")
		else:
			if not await until(func(): return FileAccess.file_exists(directory.path_join(prefix + "P-done")), "P completes the transfer"): quit(1); return
			var slot := int(FileAccess.get_file_as_string(directory.path_join("loaded-slot")))
			if not await until(func():
				var slots: Array = session.projection().belt_spans.values()[0].slots
				return slots[slot] == null if resumed else slots[slot] is Dictionary and slots[slot].get("raw") == 1,
				"Q observes the confirmed belt slot"): quit(1); return
			mark(prefix + "clients-done")
			if not await until(func(): return FileAccess.file_exists(directory.path_join(prefix + "server-done")), "Authority completes loading phase"): quit(1); return
	print("BELT_LOADING_SESSION_%s %s %d" % ["FAIL" if failed else "PASS", role, checks])
	quit(1 if failed else 0)

func run() -> void:
	if fractional_press and (overload or cog_train or span_belt or reverse_belt or middle_pulley):
		push_error("The fractional press case cannot be combined with other transmission cases")
		quit(1)
		return
	if overload and (cog_train or span_belt or reverse_belt or middle_pulley):
		push_error("The overload case cannot be combined with other transmission cases")
		quit(1)
		return
	if cog_train and (span_belt or reverse_belt or middle_pulley):
		push_error("The cog-train case cannot be combined with belt cases")
		quit(1)
		return
	if middle_pulley and (not powered_span or inclined_span or reverse_belt):
		push_error("The middle-pulley case requires the horizontal powered span")
		quit(1)
		return
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
	if belt_loading:
		await run_belt_loading()
		return
	if fractional_press:
		await run_fractional_press()
		return
	if overload:
		await run_overload()
		return
	if cog_train:
		await run_cog_train()
		return
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
		var first_pose := [1.65, 1.0, -1.65] if role == "server-resume" else [6.6, 1.0, 3.3]
		verify(session.world.publish_actor("P", first_pose, 1).get("accepted", false), "Synthetic P observation is accepted")
		verify(session.world.publish_actor("Q", [20.0, 1.0, 20.0], 1).get("accepted", false), "Synthetic Q observation is accepted")
		if failed: quit(1); return
		if role == "server-resume":
			mark("resume-server-ready")
			if not await until(func(): return FileAccess.file_exists(directory.path_join("resume-clients-done")), "Both resumed clients must finish"): quit(1); return
			verify(session.world.projection().transmission_parts.size() == 1, "The resumed authority retains the first shaft after reclaiming the second")
			verify(FileAccess.get_sha256(save_path) == input_hash, "Continued work does not modify the original save")
			if failed: quit(1); return
			mark("resume-server-done")
			finish_role()
			return
		mark("server-ready")
		if not await until(func(): return FileAccess.file_exists(directory.path_join("harvest-done")), "P harvests the finite tree through Session"): quit(1); return
		var harvested: Dictionary = session.world.projection()
		verify(harvested.cargo.P.timber == 2 and harvested.hand_sources["tree-east-south"].remaining == 6
			and harvested.part_kits.P.shaft == 0, "Harvested timber remains in native cargo before fabrication")
		verify(session.world.publish_actor("P", [3.3, 1.0, 4.8], 2).get("accepted", false), "Synthetic P reaches the pod workshop")
		if failed: quit(1); return
		mark("craft-ready")
		if not await until(func(): return FileAccess.file_exists(directory.path_join("craft-done")), "P fabricates finite shaft kits through Session"): quit(1); return
		var crafted: Dictionary = session.world.projection()
		verify(crafted.cargo.P.timber == 0 and crafted.part_kits.P.shaft == 2
			and crafted.hand_sources["tree-east-south"].remaining == 6, "The one native World conserves both fabricated shaft bills")
		verify(session.world.publish_actor("P", [1.65, 1.0, -1.65], 3).get("accepted", false), "Synthetic P reaches the construction tiles")
		if failed: quit(1); return
		mark("build-ready")
		if not await until(func(): return FileAccess.file_exists(directory.path_join("clients-done")), "Both clients must finish"): quit(1); return
		var saved: Dictionary = session.world.checkpoint()
		var fresh = NativeModel.new(session.context, ["P", "Q"], true)
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
				verify(snapshot.transmission_parts.size() == 2 and snapshot.part_kits.P.shaft == 0
					and snapshot.hand_sources["tree-east-south"].remaining == 6, "P receives two crafted shafts and depleted finite source")
				var far_shaft_id := ""
				for id in snapshot.transmission_parts:
					if snapshot.transmission_parts[id].center == [4, 4, 0]: far_shaft_id = str(id)
				verify(not far_shaft_id.is_empty(), "The saved second shaft keeps a usable identity")
				if failed: quit(1); return
				var removed: Dictionary = await issue({"action": "remove", "entity": far_shaft_id})
				verify(removed.get("accepted", false), "P removes the restored shaft through the resumed Session: " + str(removed.get("reason", "")))
				if failed: quit(1); return
				mark("resume-P-done")
			else:
				if not await until(func(): return FileAccess.file_exists(directory.path_join("resume-P-done")), "P completes continued work"): quit(1); return
				if not await until(func(): return session.projection().get("transmission_parts", {}).size() == 1, "Q observes the resumed removal"): quit(1); return
				var resumed_view: Dictionary = session.projection()
				verify(resumed_view.part_kits.P.shaft == 1 and resumed_view.hand_sources["tree-east-south"].remaining == 6,
					"Q observes one real shaft refund with no new timber")
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
			for cut in range(2):
				var harvest: Dictionary = await issue({"action": "harvest_source", "target": "tree-east-south"})
				verify(harvest.get("accepted", false), "P cuts one finite timber unit through Session: " + str(harvest.get("reason", "")))
			if failed: quit(1); return
			mark("harvest-done")
			if not await until(func(): return FileAccess.file_exists(directory.path_join("craft-ready")), "P reaches the pod workshop"): quit(1); return
			for kit in range(2):
				var crafted: Dictionary = await issue({"action": "craft_part", "entity": "pod-fabrication-hub", "role": "shaft", "half_span": 2})
				verify(crafted.get("accepted", false), "P fabricates a shaft from carried timber: " + str(crafted.get("reason", "")))
			if failed: quit(1); return
			mark("craft-done")
			if not await until(func(): return FileAccess.file_exists(directory.path_join("build-ready")), "P reaches the transmission tiles"): quit(1); return
			var shaft: Dictionary = await issue({"action": "place_shaft", "center": [0, 4, 0], "axis": "x", "half_span": 2})
			verify(shaft.get("accepted", false), "P places a one-tile shaft: " + str(shaft.get("reason", "")))
			var request: String = shaft.get("request", "")
			var duplicate: Dictionary = session.retry(request)
			verify(duplicate.get("queued", false), "P retries the original shaft request")
			if await until(func(): return replies.has(request), "Retry receives its cached outcome"):
				verify(replies[request].get("accepted", false) and replies[request].get("duplicate", false), "Retry must not spend a second shaft")
				replies.erase(request)
			var second: Dictionary = await issue({"action": "place_shaft", "center": [4, 4, 0], "axis": "z", "half_span": 2})
			verify(second.get("accepted", false), "P places a second crafted tile shaft: " + str(second.get("reason", "")))
			var invalid: Dictionary = await issue({"action": "place_shaft", "center": [5, 4, 0], "axis": "z", "half_span": 2})
			verify(not invalid.get("accepted", true) and invalid.get("reason") == "invalid_cell",
				"The authority rejects an off-grid shaft over the real wire")
			if failed: quit(1); return
			mark("P-done")
		else:
			if not await until(func(): return FileAccess.file_exists(directory.path_join("P-done")), "P completes the command sequence"): quit(1); return
			if not await until(func(): return session.projection().get("transmission_parts", {}).size() == 2, "Q observes both confirmed parts"): quit(1); return
			var view: Dictionary = session.projection()
			var centers := []
			for part in view.transmission_parts.values(): centers.append(part.center)
			verify([0, 4, 0] in centers and [4, 4, 0] in centers, "Q sees the same distinct tile centers")
			verify(view.part_kits.P.shaft == 0 and view.cargo.P.timber == 0
				and view.hand_sources["tree-east-south"].remaining == 6,
				"Q sees two installed shafts funded by exactly two finite timber cuts")
			if failed: quit(1); return
			mark("clients-done")
			if not await until(func(): return FileAccess.file_exists(directory.path_join("server-done")), "Server verifies fresh-Host restore"): quit(1); return
	finish_role()
