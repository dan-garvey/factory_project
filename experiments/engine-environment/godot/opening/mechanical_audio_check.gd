extends SceneTree
## Invented observations and Dummy audio. No authority, network or desktop.
const Opening = preload("res://opening/opening.gd")
const SharedOpening = preload("res://opening/shared_opening.gd")
const Ambience = Opening.MechanicalAmbience

class ViewFixture extends Opening:
	func _ready() -> void:
		set_process(false)

class SharedFixture extends SharedOpening:
	func _ready() -> void:
		set_process(false)

class SessionStub extends RefCounted:
	var ready := true
	func is_ready() -> bool:
		return ready

var checks := 0
var failed := false
var digital: Dictionary = {}

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)

func observation() -> Dictionary:
	var snapshot := {"context": "audio-fixture", "options": {"native": true, "physical": true},
		"actors": {"P": {"ready": true, "position": [3.0, 1.0, 5.0]}},
		"entities": {}, "motion": {}, "stock": {}, "inventories": {"P": 0}, "parts": {}}
	for kind in ["collector", "belt", "processor", "wheel"]:
		snapshot.entities[kind] = {"kind": kind, "cell": [1, 2]}
		snapshot.motion[kind] = {"state": "rotating", "numerator": 1, "denominator": 1}
	return snapshot

func check_digital() -> void:
	var output := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--preview-dir="):
			output = argument.trim_prefix("--preview-dir=")
	verify(Ambience.make_loop("unknown") == null, "Unknown kinds cannot synthesize an operating sound.")
	var signatures: Dictionary = {}
	for kind in ["collector", "belt", "processor", "wheel"]:
		var stream: AudioStreamWAV = Ambience.make_loop(kind)
		verify(stream == Ambience.make_loop(kind), "Repeated sources share their original PCM resource.")
		verify(stream.mix_rate == 44100 and stream.format == AudioStreamWAV.FORMAT_16_BITS and not stream.stereo
			and stream.data.size() == 176400 and stream.loop_begin == 0 and stream.loop_end == 88200
			and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "The original mono loop has an exact two-second extent.")
		var peak := 0.0
		var sum := 0.0
		var squares := 0.0
		var max_step := 0.0
		var last := float(stream.data.decode_s16(stream.data.size() - 2)) / 32767.0
		var first := float(stream.data.decode_s16(0)) / 32767.0
		for n in range(88200):
			var sample := float(stream.data.decode_s16(n * 2)) / 32767.0
			peak = maxf(peak, absf(sample))
			sum += sample
			squares += sample * sample
			max_step = maxf(max_step, absf(sample - last))
			last = sample
		var rms := sqrt(squares / 88200.0)
		var seam := absf(first - last)
		verify(peak < 0.23 and peak > 0.08 and rms > 0.025 and rms < 0.1,
			"Each loop has useful digital energy and retains peak headroom before its quiet game gain.")
		verify(absf(sum / 88200.0) < 0.0001 and seam < 0.02 and seam <= max_step,
			"The original loop has no material DC offset or discontinuity beyond its ordinary sample steps.")
		var signature := hash(stream.data)
		verify(not signatures.has(signature), "The four machines have distinct original loop data.")
		signatures[signature] = true
		digital[kind] = {"peak": peak, "rms": rms, "seam_step": seam}
		if not output.is_empty():
			verify(stream.save_to_wav(output.path_join(kind + ".wav")) == OK, "The exact generated stream is retained for human listening.")

func check_projection_audio() -> void:
	var bed := Ambience.new()
	root.add_child(bed)
	var snapshot := observation()
	var before: Dictionary = snapshot.duplicate(true)
	var facing := Basis(Vector3.UP, 0.7)
	bed.sync(snapshot, "P", true, facing)
	verify(bed.emitters.size() == 4 and bed.listener.is_current(), "Four confirmed rotating machines create four spatial sources.")
	if bed.emitters.size() != 4:
		bed.free()
		return
	verify(bed.listener.position == Vector3(3, 1.55, 5) and bed.listener.basis.is_equal_approx(facing),
		"Listener position follows the literal confirmed body plus its ear offset, with camera orientation only.")
	var original: AudioStreamPlayer3D = bed.emitters.belt
	for emitter in bed.emitters.values():
		verify(emitter.playing and emitter.position == Vector3(1.65, 0.7, 3.3)
			and emitter.volume_db == -23.0 and emitter.unit_size == 2.5 and emitter.max_distance == 16.0
			and emitter.max_db == -14.0 and emitter.max_polyphony == 1,
			"Each quiet spatial source occupies its confirmed machine square with a bounded audible radius.")
		verify(emitter.doppler_tracking == AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED,
			"Actor movement cannot invent machinery-speed changes through Doppler.")
	bed.sync(snapshot, "P", true, facing)
	verify(bed.emitters.belt == original and original.playing, "Unchanged observation refreshes do not restart the original source.")
	snapshot.motion.belt.numerator = -3
	snapshot.motion.belt.denominator = 2
	bed.sync(snapshot, "P", true, facing)
	verify(bed.emitters.belt == original and original.pitch_scale == 1.5,
		"Confirmed reverse rotation changes bounded timbre without reversing or replacing PCM.")
	snapshot.motion.belt.numerator = 200
	bed.sync(snapshot, "P", true, facing)
	verify(is_equal_approx(original.pitch_scale, 1.8), "An extreme observed rate is clamped only in disposable audio pitch.")
	snapshot.motion.belt = before.motion.belt.duplicate(true)
	snapshot.context = "reopened-context"
	bed.sync(snapshot, "P", true, facing)
	verify(not is_instance_valid(original) and bed.emitters.belt.stream == Ambience.make_loop("belt"),
		"A world-context change clears old playback identities while retaining reusable sound assets.")
	snapshot.entities.erase("collector")
	bed.sync(snapshot, "P", true, facing)
	verify(not bed.emitters.has("collector") and bed.emitters.size() == 3, "Removed machines lose their sound source immediately.")
	for state in ["stopped", "unpowered", "stalled", "conflicted", "unknown"]:
		snapshot.motion.belt.state = state
		bed.sync(snapshot, "P", true, facing)
		verify(not bed.emitters.has("belt"), "Only an explicit rotating state permits machinery audio.")
	for malformed in [{"state": "rotating", "numerator": true, "denominator": 1},
		{"state": "rotating", "numerator": 1.0, "denominator": 1},
		{"state": "rotating", "numerator": 1, "denominator": 0},
		{"state": "rotating", "numerator": 1, "denominator": -1},
		{"state": "rotating", "numerator": 0, "denominator": 1},
		{"state": "rotating", "numerator": 1, "denominator": 1.0}]:
		snapshot.motion.belt = malformed
		bed.sync(snapshot, "P", true, facing)
		verify(not bed.emitters.has("belt"), "Malformed or zero rates cannot produce a false operating sound.")
	for pose in [[3, 1, 5, 0], [true, 1, 5], [NAN, 1, 5], [INF, 1, 5]]:
		var invalid := observation()
		invalid.actors.P.position = pose
		bed.sync(invalid, "P", true, facing)
		verify(bed.emitters.is_empty() and not bed.listener.is_current(), "Invalid actor coordinates clear the sound bed.")
	bed.sync(before, "P", false, facing)
	verify(bed.emitters.is_empty(), "An unready/disconnected view cannot replay its retained operation.")
	var historical := before.duplicate(true)
	historical.options.native = false
	bed.sync(historical, "P", true, facing)
	verify(bed.emitters.is_empty(), "A historical powered flag is not substituted for native motion facts.")
	bed.sync(before, "Q", true, facing)
	verify(bed.emitters.is_empty(), "An absent local participant cannot borrow the other actor's ears.")
	bed.sync(before, "P", true, Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO))
	verify(bed.emitters.is_empty(), "A degenerate camera basis cannot invent spatial orientation.")
	verify(before == observation(), "Audio operations leave the original observation byte/type values intact.")
	bed.silence()
	bed.free()
	var range_bed := Ambience.new()
	root.add_child(range_bed)
	var range_snapshot := observation()
	range_snapshot.entities.wheel.cell = [100, 100]
	range_bed.sync(range_snapshot, "P", true, facing)
	verify(range_bed.emitters.size() == 3 and not range_bed.emitters.has("wheel"),
		"A rotating source beyond its authored 16-meter audio limit creates no emitter.")
	range_snapshot.actors.P.position = [165.0, 1.0, 165.0]
	range_bed.sync(range_snapshot, "P", true, facing)
	verify(range_bed.emitters.size() == 1 and range_bed.emitters.has("wheel")
		and range_bed.emitters.wheel.stream == Ambience.make_loop("wheel"),
		"Walking into range starts the original wheel sound and removes distant sources.")
	var nearby_wheel: AudioStreamPlayer3D = range_bed.emitters.get("wheel")
	range_snapshot.actors.P.position = [3.0, 1.0, 5.0]
	range_bed.sync(range_snapshot, "P", true, facing)
	verify(range_bed.emitters.size() == 3 and not is_instance_valid(nearby_wheel),
		"Leaving range releases the formerly audible source.")
	range_snapshot.motion.wheel.state = "stopped"
	range_snapshot.actors.P.position = [165.0, 1.0, 165.0]
	range_bed.sync(range_snapshot, "P", true, facing)
	verify(range_bed.emitters.is_empty(), "Returning to a stopped distant wheel remains silent.")
	range_bed.silence()
	range_bed.free()
	var crowded_bed := Ambience.new()
	root.add_child(crowded_bed)
	var crowded := observation()
	crowded.entities.clear()
	crowded.motion.clear()
	for index in 1000:
		var id := "distant-wheel-%d" % index
		crowded.entities[id] = {"kind": "wheel", "cell": [100 + index % 40, 100 + floori(float(index) / 40.0)]}
		crowded.motion[id] = {"state": "rotating", "numerator": 1, "denominator": 1}
	crowded.entities["local_wheel"] = {"kind": "wheel", "cell": [1, 2]}
	crowded.motion["local_wheel"] = {"state": "rotating", "numerator": 1, "denominator": 1}
	crowded_bed.sync(crowded, "P", true, facing)
	verify(crowded_bed.emitters.size() == 1 and crowded_bed.emitters.has("local_wheel"),
		"A thousand silent distant wheels do not allocate sound players around one nearby source.")
	crowded_bed.silence()
	crowded_bed.free()

func check_view_callbacks(shared: bool) -> void:
	var view = SharedFixture.new() if shared else ViewFixture.new()
	view.state = observation()
	if shared:
		view.session = SessionStub.new()
	root.add_child(view)
	view.camera = Camera3D.new()
	view.add_child(view.camera)
	view._refresh_mechanical_audio()
	verify(view.mechanical_ambience.emitters.size() == 4, "The actual view refresh reaches the confirmed-motion sound bed.")
	if view.mechanical_ambience.emitters.size() != 4:
		view.free()
		return
	if shared:
		view.pending_actions = {"request": {"action": {"action": "place"}}}
		view._refresh_mechanical_audio()
		verify(view.mechanical_ambience.emitters.size() == 4, "An unrelated pending build does not falsely stop confirmed shaft motion.")
		view.session.ready = false
		view._refresh_mechanical_audio()
		verify(view.mechanical_ambience.emitters.is_empty(), "Shared connection loss silences the last confirmed snapshot.")
		view.session.ready = true
	view.explanation_open = true
	view._refresh_mechanical_audio()
	verify(view.mechanical_ambience.emitters.is_empty(), "Help uses its own quiet presentation space.")
	view.explanation_open = false
	view.state.actors.P.ready = false
	view._refresh_mechanical_audio()
	verify(view.mechanical_ambience.emitters.is_empty(), "Lost physical readiness silences machine operation.")
	verify(view.model == null and view.actor_world == null and view.request_sequence == 0,
		"The isolated actual view callback creates no authority, actor or request.")
	view.mechanical_ambience.silence()
	view.free()

func _initialize() -> void:
	if "--scene-only" not in OS.get_cmdline_user_args():
		check_digital()
	# SceneTree._initialize runs before the root enters the tree. Real 3D audio
	# needs that boundary; deferred execution changes no product lifecycle.
	call_deferred("_check_scene")

func _check_scene() -> void:
	check_projection_audio()
	check_view_callbacks(false)
	check_view_callbacks(true)
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks, "digital": digital,
		"observations": "invented", "audible_quality": "not_assessed", "desktop": "not_used"}))
	quit(1 if failed else 0)
