extends SceneTree
## Invented decisions check presentation guards. No authority or desktop starts.
const Audio = preload("res://opening/construction_audio.gd")
var checks := 0
var failed := false
var preview_directory := ""
var samples: Array = []
const IMPACT_PINS := {
	"impactMetal_light_001.ogg": "fba69c467ddd85da7b1d82e259f936b876d9ba6a3d6f1b24bdd10468e46bfe08",
	"impactMetal_light_003.ogg": "92d5db6bfc672d9dc1b4f390b2900504f013187fa36335472554fafefa9050b1",
	"impactMetal_light_004.ogg": "9b1c35820fba507081261f19ab5f461f69a5e2627a7d91acdb73ca3cfc997979",
	"impactMetal_medium_002.ogg": "7e89ce2ca0dbda95ea2b78d4b50791cab35c10d20e9f5ccd45dd0b00e99ff548",
	"impactSoft_heavy_000.ogg": "49e7ca88743fca974bb8676ea138b751cfd8f9033b5e7af8736c2a215d6edbc1",
	"impactSoft_medium_001.ogg": "7642a4fd43e547afe4f7adfadb3dabb681c0ff512f52c1674bae30a726841faf",
	"impactWood_heavy_001.ogg": "f1b07a53ac10c615fff9ba470511fdeb722b5902e1a8520759fc20ad6f546015"}
const IMPACT_RECIPE := {
	"belt_snap": {"duration": 0.42, "layers": [["impactSoft_heavy_000.ogg", 0.0, 0.72], ["impactMetal_light_003.ogg", 0.035, 0.38]]},
	"assembly": {"duration": 0.42, "layers": [["impactWood_heavy_001.ogg", 0.0, 0.65], ["impactMetal_medium_002.ogg", 0.015, 0.7]]},
	"coupling": {"duration": 0.28, "layers": [["impactMetal_light_001.ogg", 0.0, 1.0]]},
	"release": {"duration": 0.26, "layers": [["impactSoft_medium_001.ogg", 0.0, 0.55], ["impactMetal_light_004.ogg", 0.012, 0.35]]}}

func prepare_impact_cues() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3 or AudioServer.get_mix_rate() != 44100:
		push_error("Use --prepare-impact-cues SOURCE OUTPUT with the pinned 44100 Hz mixer.")
		quit(1)
		return
	var source := args[1]
	var output := args[2]
	for cue in IMPACT_RECIPE:
		if FileAccess.file_exists(output.path_join(cue + ".wav")):
			push_error("Refuse an existing prepared construction cue.")
			quit(1)
			return
	for file in IMPACT_PINS:
		if FileAccess.get_sha256(source.path_join(file)) != IMPACT_PINS[file]:
			push_error("Refuse an unpinned impact source: " + file)
			quit(1)
			return
	var decoded: Dictionary = {}
	var report := {"status": "pass", "mix_rate": 44100, "sources": {}, "cues": {}}
	for file in IMPACT_PINS:
		var input := AudioStreamOggVorbis.load_from_file(source.path_join(file))
		if input == null or input.get_length() <= 0.0 or input.get_length() > 1.0:
			push_error("Invalid bounded source impact: " + file)
			quit(1)
			return
		input.loop = false
		var playback := input.instantiate_playback()
		playback.start()
		var frames := playback.mix_audio(1.0, ceili(input.get_length() * 44100.0) + 256)
		playback.stop()
		var mono := PackedFloat32Array()
		mono.resize(frames.size())
		var peak := 0.0
		var valid := true
		for n in range(frames.size()):
			mono[n] = (frames[n].x + frames[n].y) * 0.5
			valid = valid and is_finite(mono[n])
			peak = maxf(peak, absf(mono[n]))
		if mono.is_empty() or not valid or not is_finite(peak) or peak < 0.001 or peak > 2.0:
			push_error("The decoded impact is silent or invalid: " + file)
			quit(1)
			return
		decoded[file] = mono
		report.sources[file] = {"frames": frames.size(), "mono_peak": peak}
	for cue in IMPACT_RECIPE:
		var recipe: Dictionary = IMPACT_RECIPE[cue]
		var count := roundi(recipe.duration * 44100.0)
		var mixed := PackedFloat32Array()
		mixed.resize(count)
		for layer in recipe.layers:
			var input: PackedFloat32Array = decoded[layer[0]]
			var offset := roundi(layer[1] * 44100.0)
			for n in range(mini(input.size(), count - offset)):
				mixed[n + offset] += input[n] * layer[2]
		var peak := 0.0
		for n in range(count):
			var t := float(n) / 44100.0
			mixed[n] *= minf(1.0, t / 0.0025) * clampf((recipe.duration - t) / 0.03, 0.0, 1.0)
			peak = maxf(peak, absf(mixed[n]))
		if not is_finite(peak) or peak < 0.001:
			push_error("The impact mix has no usable signal: " + cue)
			quit(1)
			return
		var pcm := PackedByteArray()
		pcm.resize(count * 2)
		var sum_squares := 0.0
		for n in range(count):
			var sample := mixed[n] * (0.62 / peak) if n > 0 and n < count - 1 else 0.0
			pcm.encode_s16(n * 2, roundi(sample * 32767.0))
			sum_squares += sample * sample
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = 44100
		wav.stereo = false
		wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
		wav.data = pcm
		var path := output.path_join(cue + ".wav")
		if wav.save_to_wav(path) != OK:
			push_error("Cannot save prepared impact cue: " + cue)
			quit(1)
			return
		var loaded := AudioStreamWAV.load_from_file(path)
		if loaded == null or loaded.data != pcm or loaded.mix_rate != 44100 or loaded.stereo or loaded.format != AudioStreamWAV.FORMAT_16_BITS:
			push_error("Prepared cue PCM changed on roundtrip: " + cue)
			quit(1)
			return
		report.cues[cue] = {"frames": count, "duration": recipe.duration, "peak": 0.62,
			"rms": sqrt(sum_squares / count), "exact_pcm_roundtrip": true, "sha256": FileAccess.get_sha256(path)}
	print(JSON.stringify(report))
	quit(0)

class AuthorityStub:
	extends RefCounted
	var accepts := true
	var duplicate := false
	func projection() -> Dictionary:
		return {"context": "audio-fixture"}
	func command(wire: Dictionary) -> Dictionary:
		return {"accepted": accepts, "duplicate": duplicate, "reason": "ok" if accepts else "occupied",
			"context": wire.context, "client": wire.client, "request": wire.request, "entity": "fixture-belt"}

class OfflineFixture:
	extends "res://opening/opening.gd"
	func _ready() -> void:
		set_process(false)
	func _refresh() -> void:
		pass
	func _message(_words: String, _bad: bool = false) -> void:
		pass

class SessionStub:
	extends RefCounted
	var ready := true
	var request_sequence := 0
	var request_namespace := "audio-shared-"
	func is_ready() -> bool:
		return ready
	func projection() -> Dictionary:
		return {"context": "audio-fixture"}
	func submit(_action: Dictionary) -> Dictionary:
		request_sequence += 1
		return {"accepted": false, "queued": true, "request": request_namespace + str(request_sequence)}

class SharedFixture:
	extends "res://opening/shared_opening.gd"
	func _ready() -> void:
		set_process(false)
	func _usable_snapshot() -> bool:
		return true
	func _refresh() -> void:
		_settle_pending()
	func _message(_words: String, _bad: bool = false) -> void:
		pass

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)

func _initialize() -> void:
	if OS.get_cmdline_user_args().size() > 0 and OS.get_cmdline_user_args()[0] == "--prepare-impact-cues":
		prepare_impact_cues()
		return
	if OS.get_cmdline_user_args().has("--cache-release-only"):
		call_deferred("run_cache_release")
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--audio-preview-directory="):
			preview_directory = argument.trim_prefix("--audio-preview-directory=")
	call_deferred("run")

func receipt(wire: Dictionary) -> Dictionary:
	return {"accepted": true, "context": wire.context, "client": wire.client, "request": wire.request}

func check_guards() -> void:
	var audio := Audio.new()
	root.add_child(audio)
	var events: Array = []
	audio.cue_emitted.connect(func(cue: String, identity: Array): events.append([cue, identity.duplicate()]))
	var wire := {"action": "place", "kind": "belt", "context": "audio-fixture", "client": "P", "request": "r1"}
	var result := receipt(wire)
	for alteration in [{"accepted": false}, {"accepted": 1}, {"queued": true}, {"queued": 1},
		{"duplicate": true}, {"duplicate": 1}, {"client": "Q"}, {"context": "other"}, {"request": "other"}]:
		var wrong := result.duplicate(true)
		wrong.merge(alteration, true)
		verify(not audio.confirmed(wire, wrong, "audio-fixture") and events.is_empty(),
			"Refused, queued, duplicate, mistyped and mismatched decisions cannot play a success cue.")
	verify(not audio.confirmed(wire, result, "another-live-world") and events.is_empty(),
		"An old world receipt cannot trigger sound in the current worksite.")
	verify(audio.confirmed(wire, result, "audio-fixture") and events.size() == 1 and events[0][0] == "belt_snap",
		"A matching fresh belt decision emits exactly one belt-attachment cue.")
	verify(not audio.confirmed(wire, result, "audio-fixture") and events.size() == 1,
		"A repeated decision callback cannot replay the cue.")
	var power := wire.duplicate(true)
	power["action"] = "retrieve"
	verify(not audio.confirmed(power, result, "audio-fixture") and events.size() == 1,
		"Unrelated accepted operations do not become construction events.")
	wire["context"] = "new-world"
	verify(audio.confirmed(wire, receipt(wire), "new-world") and events.size() == 2,
		"Separate worlds retain separate action identities.")
	audio.free()

func check_modular_cues() -> void:
	var expected := {
		"place_belt_span": "belt_snap", "place_selected_belt_span": "belt_snap",
		"place_foundation": "assembly", "place_foundations": "assembly",
		"place_component": "assembly", "deploy_fabrication_hub": "assembly",
		"craft_component": "assembly", "field_craft": "assembly", "craft_part": "assembly",
		"turn_press_crank": "assembly",
		"place_gear": "coupling", "place_shaft": "coupling", "place_relay": "coupling",
		"shaft_between": "coupling", "remove_belt_span": "release",
		"remove_shaft_between": "release", "remove_foundation": "release",
		"reclaim_component": "release", "stow_fabrication_hub": "release"}
	for action: String in expected:
		verify(Audio.cue_for({"action": action}) == expected[action],
			"A confirmed modular construction action chooses its intended existing cue.")
	for action in ["select_belt_shaft", "set_drive", "load_belt_slot", "feed_press"]:
		verify(Audio.cue_for({"action": action}).is_empty(),
			"A selection, control or material transfer cannot sound like accepted construction.")

func check_actual_hooks() -> void:
	var native_belt := {"action": "place_selected_belt_span", "from": "shaft-a",
		"to": "shaft-b", "selection": "first-shaft-request"}
	var offline := OfflineFixture.new()
	root.add_child(offline)
	var authority := AuthorityStub.new()
	offline.model = authority
	authority.accepts = false
	offline.issue(native_belt)
	verify(offline.construction_audio == null, "The actual offline refusal path does not create a construction cue.")
	authority.accepts = true
	offline.issue(native_belt)
	verify(offline.construction_audio != null and offline.construction_audio.heard.size() == 1
		and offline.construction_audio.stream == Audio.make_stream("belt_snap"),
		"The actual offline issue path forwards its matched accepted identity to the belt cue.")
	authority.duplicate = true
	offline.issue(native_belt)
	verify(offline.construction_audio != null and offline.construction_audio.heard.size() == 1,
		"A cached duplicate is silent through the actual offline path.")
	authority.duplicate = false
	authority.accepts = false
	var press_turn := {"action": "turn_press_crank", "entity": "press-anvil"}
	offline.issue(press_turn)
	verify(offline.construction_audio.heard.size() == 1,
		"A refused hand turn stays silent in the ordinary offline path.")
	authority.accepts = true
	offline.issue(press_turn)
	verify(offline.construction_audio.heard.size() == 2
		and offline.construction_audio.stream == Audio.make_stream("assembly"),
		"One confirmed hand turn plays the short existing impact cue.")
	authority.duplicate = true
	offline.issue(press_turn)
	verify(offline.construction_audio.heard.size() == 2,
		"A replayed hand turn cannot repeat the work cue.")
	offline.free()
	var shared := SharedFixture.new()
	root.add_child(shared)
	shared.client = "P"
	shared.session = SessionStub.new()
	shared.model = shared.session
	shared.state = {"context": "audio-fixture", "revision": 2, "order": 2, "entities": {"fixture-belt": {"kind": "belt"}}}
	var queued: Dictionary = shared.issue(native_belt)
	verify(queued.queued and shared.construction_audio == null,
		"The actual shared queued path remains silent before a server decision.")
	var outcome := {"accepted": true, "context": "audio-fixture", "client": "P", "request": queued.request,
		"revision": 3, "order": 3, "entity": "fixture-belt"}
	shared._outcome_received(outcome)
	verify(shared.construction_audio == null and shared.pending_actions.size() == 1,
		"A decision ahead of the confirmed snapshot remains silent.")
	shared.state["revision"] = 3
	shared.state["order"] = 3
	shared._settle_pending()
	verify(shared.construction_audio != null and shared.construction_audio.heard.size() == 1
		and shared.pending_actions.is_empty(), "The actual matched shared settlement emits its cue once.")
	shared._outcome_received(outcome)
	shared._refresh()
	verify(shared.construction_audio.heard.size() == 1, "Repeated envelopes and refreshes cannot replay a settled cue.")
	shared.session.ready = false
	shared.issue(native_belt)
	verify(shared.construction_audio.heard.size() == 1, "The disconnected shared path stays silent.")
	shared.free()

func check_samples() -> void:
	for cue in ["belt_snap", "assembly", "coupling", "release"]:
		var stream: AudioStreamWAV = Audio.make_stream(cue)
		verify(stream == Audio.make_stream(cue) and stream.mix_rate == 44100
			and not stream.stereo and stream.format == AudioStreamWAV.FORMAT_16_BITS
			and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Short sound resources are shared and never loop.")
		var data := stream.data
		var peak := 0.0
		var energy := 0.0
		for offset in range(0, data.size(), 2):
			var value := float(data.decode_s16(offset)) / 32768.0
			peak = maxf(peak, absf(value))
			energy += value * value
		var rms := sqrt(energy / float(data.size() / 2))
		verify(stream.get_length() >= 0.15 and stream.get_length() <= 0.43 and peak < 0.8 and rms > 0.005,
			"Each prepared or historical cue has finite duration, signal energy and digital headroom.")
		verify(data.decode_s16(0) == 0 and data.decode_s16(data.size() - 2) == 0,
			"Cues start and end at zero to avoid a hard boundary click.")
		if not preview_directory.is_empty():
			var target := preview_directory.path_join(cue + ".wav")
			verify(not FileAccess.file_exists(target) and stream.save_to_wav(target) == OK,
				"Retain each original cue for later human listening without replacing an artifact.")
		samples.append({"cue": cue, "bytes": data.size(), "seconds": stream.get_length(), "peak": peak, "rms": rms})
	verify(Audio.make_stream("unrecognized") == null, "Unknown events cannot invent an audio asset.")
	var historical := OS.get_cmdline_user_args().has("--historical-samples")
	verify(Audio.source_status == ("missing" if historical else "ready"),
		"The actual captured file set, not a runtime switch, selects prepared or historical cues.")
	if not historical:
		for cue in Audio.FILES:
			var data := Audio.make_stream(cue).data
			verify(data == AudioStreamWAV.load_from_file(Audio.ROOT.path_join(Audio.FILES[cue])).data,
				"Actual playback consumes the prepared PCM without runtime mixing or normalization.")
	verify(Audio.read_samples("user://cue-controls/missing").status == "missing", "An absent set is explicit.")
	var partial := "user://cue-controls/partial"
	DirAccess.make_dir_recursive_absolute(partial)
	var file := FileAccess.open(partial.path_join("belt_snap.wav"), FileAccess.WRITE)
	if file != null:
		file.store_string("partial control")
		file.close()
	verify(file != null and Audio.read_samples(partial).status == "invalid", "Partial sets cannot claim prepared cues.")
	var old_streams: Dictionary = Audio.streams
	var old_status := Audio.source_status
	Audio.streams = {}
	Audio.source_status = "invalid"
	var silent := Audio.new()
	root.add_child(silent)
	var action := {"action": "place", "kind": "belt", "context": "unavailable", "client": "P", "request": "1"}
	verify(not silent.confirmed(action, receipt(action), "unavailable") and silent.heard.is_empty(),
		"Unavailable audio neither emits a cue nor remembers an unplayed acknowledgement.")
	silent.free()
	Audio.streams = old_streams
	Audio.source_status = old_status

func release_samples() -> bool:
	var references: Array[WeakRef] = []
	for cue in Audio.streams.keys():
		references.append(weakref(Audio.streams[cue]))
	Audio.streams.clear()
	Audio.source_status = "uninitialized"
	var deadline := Time.get_ticks_msec() + 2000
	while true:
		var remaining := 0
		for reference in references:
			if reference.get_ref() != null:
				remaining += 1
		if remaining == 0:
			return true
		if Time.get_ticks_msec() >= deadline:
			push_error("Audio fixture still owns %d sample resources after release." % remaining)
			return false
		await process_frame
	return false

func run_cache_release() -> void:
	for cue in Audio.FILES:
		verify(Audio.make_stream(cue) != null, "The actual prepared sample enters its shared cache.")
	verify(await release_samples(), "Fixture teardown releases every actual sample through weak-reference observation.")
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
		"mode": "cache-release-only", "authority_started": false, "desktop": "not_used"}))
	quit(1 if failed else 0)

func run() -> void:
	if not preview_directory.is_empty():
		if not preview_directory.is_absolute_path() or preview_directory.begins_with(ProjectSettings.globalize_path("res://")):
			verify(false, "Preview output must be an explicit external artifact directory.")
			quit(1)
			return
		DirAccess.make_dir_recursive_absolute(preview_directory)
	check_guards()
	check_modular_cues()
	check_actual_hooks()
	check_samples()
	var observed_source_status := Audio.source_status
	verify(await release_samples(), "The fixture releases its sample cache before exiting.")
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks, "samples": samples, "source_status": observed_source_status,
		"scope": "invented confirmation guards, actual view callbacks and captured PCM assets",
		"native_decisions": "not_run", "audible_quality": "not_assessed", "desktop": "not_used"}))
	quit(1 if failed else 0)
