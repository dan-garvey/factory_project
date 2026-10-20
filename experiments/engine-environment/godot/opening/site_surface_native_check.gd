extends SceneTree
## Headless producer/Store integration. No player input, renderer or desktop.
const Opening = preload("res://opening/opening.gd")
const NativeModel = preload("res://opening/native_model.gd")
const Session = preload("res://opening-session/session.gd")
const ActorWorld = preload("res://opening/actor_world.gd")
const Surface = preload("res://opening/site_surface.gd")
const Store = preload("res://save-tests/checkpoint_file.gd")

class PhysicalView extends Opening:
	var faults: Array = []
	func _ready() -> void:
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
	func _refresh() -> void:
		state = model.projection()
	func _actor_failed(actor: String, reason: String) -> void:
		faults.append({"actor": actor, "reason": reason})
		model.invalidate_actor(actor)

var checks := 0
var failed := false
var directory := ""
var view
var session
var session_host
var negative_world
var resume_input := ""
var facts: Dictionary = {"scope": "native terrain producer and Store adapter",
	"desktop": "not_used", "human_play": "not_run", "steps": []}

func verify(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		if not failed:
			facts.failure = message
		failed = true
		push_error(message)
	return condition

func until(predicate: Callable, frames: int, message: String) -> bool:
	for frame in range(frames):
		if view != null and not view.faults.is_empty():
			facts.producer_faults = view.faults.duplicate(true)
			return verify(false, "Unexpected producer failure: " + message)
		if predicate.call():
			return verify(true, message)
		await physics_frame
	return verify(false, "Physics-frame limit: " + message)

func grounded(world: Node3D) -> bool:
	for actor in ["P", "Q"]:
		var sample: Dictionary = world.diagnostics(actor).sample
		if not sample.get("ready", false) or not sample.get("registered", false) or not sample.get("on_floor", false) or sample.get("body_ticks", 0) < 1:
			return false
	return true

func digest(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()

func finish() -> void:
	if view != null:
		if view.actor_world != null:
			view.actor_world.release_control("P")
		view.free()
		view = null
	if session != null:
		session.close()
		session.free()
		session = null
	if session_host != null:
		session_host.free()
		session_host = null
	if negative_world != null:
		negative_world.free()
		negative_world = null
	facts.status = "fail" if failed else "pass"
	facts.checks = checks
	var output := FileAccess.open(directory.path_join("native-result.json"), FileAccess.WRITE) if directory.is_absolute_path() else null
	if output != null:
		output.store_string(JSON.stringify(facts, "  ") + "\n")
		output.close()
	print(JSON.stringify({"status": facts.status, "checks": checks, "scope": facts.scope, "desktop": "not_used"}))
	quit(1 if failed else 0)

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--artifacts="):
			directory = argument.trim_prefix("--artifacts=")
		elif argument.begins_with("--resume-input="):
			resume_input = argument.trim_prefix("--resume-input=")
	call_deferred("run_case")

func run_case() -> void:
	if not verify(directory.is_absolute_path() and DirAccess.dir_exists_absolute(directory), "Use the owned external artifact directory"):
		finish()
		return
	var authority = NativeModel.new("terrain-physical-fixture", ["P", "Q"])
	if not verify(authority.boot_result.get("accepted", false), "The accepted native library owns the sole factory state"):
		finish()
		return
	if not resume_input.is_empty():
		if not verify(resume_input.is_absolute_path() and Store.read_into(authority, resume_input).accepted,
			"The focused mount correction uses the original typed binary from the retained successful movement/save prefix"):
			finish()
			return
		var loaded_checkpoint: Dictionary = authority.checkpoint().duplicate(true)
		var loaded_bytes := FileAccess.get_file_as_bytes(resume_input)
		facts.reused_input = {"path": resume_input, "sha256": digest(loaded_bytes), "scope": "Original movement/save and buried-pose controls are not repeated."}
		authority = null
		await check_restore(loaded_checkpoint, loaded_bytes, resume_input)
		return
	var seed: Dictionary = authority.checkpoint()
	seed.actors.Q = [30.0, 8.0, 1.65]
	facts.controlled_seed = seed.actors.duplicate(true)
	if not verify(authority.restore_checkpoint(seed).get("accepted", false), "The declared literal hill seed is schema-valid before native registration"):
		finish()
		return
	view = PhysicalView.new()
	view.model = authority
	view.client = "P"
	view.status_label = Label.new()
	view.add_child(view.status_label)
	root.add_child(view)
	if not verify(view._start_character_world(), "The ordinary offline factory constructs the actual physical producer"):
		finish()
		return
	if not (await until(func() -> bool: return grounded(view.actor_world), 300, "The pad and literal-hill actors become registered and grounded")):
		finish()
		return
	var ray := PhysicsRayQueryParameters3D.create(Vector3(30, 30, 1.65), Vector3(30, -10, 1.65), 1)
	var hit: Dictionary = view.actor_world.get_world_3d().direct_space_state.intersect_ray(ray)
	if not verify(not hit.is_empty() and absf(hit.position.y - 6.222421626752348) < 0.00001,
		"The actual native surface ray retains the original emitted-triangle counterexample height"):
		finish()
		return
	facts.literal_hill = {"ray": [hit.position.x, hit.position.y, hit.position.z],
		"actor_Q": view.actor_world.diagnostics("Q").duplicate(true)}
	if not verify(view.actor_world.set_control("P", Vector2.RIGHT, false).accepted,
		"The trusted ordinary motor receives a walking direction from the flat pad"):
		finish()
		return
	var reached := false
	var jumped_curb := false
	for frame in range(1000):
		await physics_frame
		if not view.faults.is_empty():
			break
		var sample: Dictionary = view.actor_world.diagnostics("P").sample
		facts.steps.append(sample.duplicate(true))
		if not jumped_curb and sample.position[0] >= 7.6 and sample.on_floor:
			jumped_curb = true
			if not verify(view.actor_world.set_control("P", Vector2.RIGHT, true).accepted,
				"The ordinary jump motor crosses the actual visible foundry curb rather than ignoring its collision"):
				break
		if not verify(sample.registered and sample.position == authority.projection().actors.P.position,
			"Native movement and the authority bridge retain the same actual three-coordinate pose"):
			break
		if sample.position[0] >= 30.0:
			reached = true
			break
	view.actor_world.release_control("P")
	if not verify(reached and jumped_curb and view.faults.is_empty(), "The physical actor walks and jumps the visible curb to reach the hillside without a position reset"):
		finish()
		return
	if not (await until(func() -> bool: return grounded(view.actor_world), 120, "Released actors remain supported by the physical site")):
		finish()
		return
	view.configure_save_slot(directory.path_join("surface.factory"))
	var saved: Dictionary = view._save_worksite()
	if not verify(saved.accepted and saved.native_preflight.accepted,
		"The ordinary offline save guard supports the new registered shapes and writes the real Store binary"):
		finish()
		return
	var checkpoint: Dictionary = authority.checkpoint().duplicate(true)
	var original := FileAccess.get_file_as_bytes(view.save_slot)
	facts.saved = {"checkpoint": checkpoint, "native_preflight": saved.native_preflight,
		"sha256": digest(original), "bytes": original.size()}
	view.free()
	view = null
	authority = null
	await physics_frame
	await check_restore(checkpoint, original, directory.path_join("surface.factory"))

func check_restore(checkpoint: Dictionary, original: PackedByteArray, save_path: String) -> void:
	var probe := PacketPeerUDP.new()
	if not verify(probe.bind(0, "127.0.0.1") == OK, "Select an ephemeral loopback port for the actual server constructor"):
		finish()
		return
	var port := probe.get_local_port()
	probe.close()
	session = Session.new()
	session.name = "Session"
	session_host = Node.new()
	session_host.name = "OpeningShared"
	root.add_child(session_host)
	session_host.add_child(session)
	if not verify(session.serve_loopback(port, true, true, ["P", "Q"], true) == OK,
		"The ordinary shared-server entry creates a fresh native authority with no clients"):
		finish()
		return
	if not verify(Store.read_into(session.world, save_path).accepted
		and session.world.checkpoint() == checkpoint, "The actual binary restores every typed field before any new body is created"):
		finish()
		return
	session.context = session.world.context
	if not verify(session.start_physical_world() == OK, "The ordinary authoritative server constructs the same terrain producer after Store load"):
		finish()
		return
	if not (await until(func() -> bool: return session.physical_ready() and grounded(session.actor_world), 300,
		"Fresh registered server bodies support the saved hillside poses")):
		finish()
		return
	for actor in ["P", "Q"]:
		var diagnostics: Dictionary = session.actor_world.diagnostics(actor)
		if not verify(diagnostics.declared_seed == checkpoint.actors[actor]
			and diagnostics.sample.control == [0.0, 0.0] and not diagnostics.sample.jump_queued,
			"The restored source seed is preserved and controls are released: " + actor):
			finish()
			return
	facts.restored = {"samples": session.actor_world.diagnostics(), "checkpoint": session.world.checkpoint()}
	if not verify(session.actor_world.checkpoint_status().accepted
		and FileAccess.get_file_as_bytes(save_path) == original,
		"Fresh contact validation preserves the original saved bytes"):
		finish()
		return
	session.close()
	session.free()
	session = null
	session_host.free()
	session_host = null
	await physics_frame
	probe = PacketPeerUDP.new()
	if not verify(probe.bind(port, "127.0.0.1") == OK, "The original shared-server port is released"):
		finish()
		return
	probe.close()
	if not resume_input.is_empty():
		facts.limits = "Focused Session mount/Store reopen only; original movement/save and buried-pose records are reused. One engine, no fresh OS-process or ordinary client play."
		finish()
		return
	var authority = NativeModel.new("buried-fixture", ["P", "Q"])
	var buried: Dictionary = checkpoint.duplicate(true)
	buried.actors.Q = [30.0, 0.88, 1.65]
	if not verify(authority.restore_checkpoint(buried).accepted, "The retained buried seed passes only schema validation, before physical validation"):
		finish()
		return
	negative_world = ActorWorld.new()
	negative_world.pose_published.connect(func(actor: String, sample: Dictionary): authority.publish_actor(actor, sample.position, sample.native_epoch))
	negative_world.initialization_failed.connect(func(actor: String, _reason: String): authority.invalidate_actor(actor))
	if not verify(negative_world.configure(authority).accepted, "Configure the unchanged producer for the declared negative physical fixture"):
		finish()
		return
	root.add_child(negative_world)
	for actor in ["P", "Q"]:
		negative_world.ensure_actor(actor)
	if not (await until(func() -> bool: return negative_world.failures.has("Q"), 180, "The original buried hill pose is refused by native initialization")):
		finish()
		return
	var negative: Dictionary = negative_world.diagnostics("Q")
	var represented_seed := Vector3(30.0, 0.88, 1.65)
	if not verify(negative.failure == "actor_saved_pose_overlaps" and negative.declared_seed == [30.0, 0.88, 1.65]
		and negative.sample.position == [represented_seed.x, represented_seed.y, represented_seed.z]
		and authority.projection().actors.Q.position == [30.0, 0.88, 1.65]
		and not negative_world.bodies.Q.motion_enabled and not authority.projection().actors.Q.ready,
		"A wholly buried capsule is refused without moving its saved pose or publishing readiness"):
		finish()
		return
	facts.negative = negative
	facts.limits = "One engine with sequential fresh producer/Core lifetimes; no fresh OS-process or ordinary client-play claim. The negative schema-valid fixture is explicit. No material command, camera authority or desktop input is used."
	finish()
