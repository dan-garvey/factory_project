extends SceneTree
## Invented decisions check presentation guards. No authority or desktop starts.
const Opening = preload("res://opening/opening.gd")
const Audio = Opening.ConstructionAudio
var checks := 0
var failed := false
var preview_directory := ""
var samples: Array = []

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
	power["action"] = "set_power"
	verify(not audio.confirmed(power, result, "audio-fixture") and events.size() == 1,
		"Unrelated accepted operations do not become construction events.")
	wire["context"] = "new-world"
	verify(audio.confirmed(wire, receipt(wire), "new-world") and events.size() == 2,
		"Separate worlds retain separate action identities.")
	audio.free()

func check_actual_hooks() -> void:
	var offline := OfflineFixture.new()
	root.add_child(offline)
	var authority := AuthorityStub.new()
	offline.model = authority
	authority.accepts = false
	offline.issue({"action": "place", "kind": "belt", "cell": [0, 0]})
	verify(offline.construction_audio == null, "The actual offline refusal path does not create a construction cue.")
	authority.accepts = true
	offline.issue({"action": "place", "kind": "belt", "cell": [0, 0]})
	verify(offline.construction_audio != null and offline.construction_audio.heard.size() == 1
		and offline.construction_audio.stream == Audio.make_stream("belt_snap"),
		"The actual offline issue path forwards its matched accepted identity to the belt cue.")
	authority.duplicate = true
	offline.issue({"action": "place", "kind": "belt", "cell": [0, 0]})
	verify(offline.construction_audio.heard.size() == 1, "A cached duplicate is silent through the actual offline path.")
	offline.free()
	var shared := SharedFixture.new()
	root.add_child(shared)
	shared.client = "P"
	shared.session = SessionStub.new()
	shared.model = shared.session
	shared.state = {"context": "audio-fixture", "revision": 2, "order": 2, "entities": {"fixture-belt": {"kind": "belt"}}}
	var queued: Dictionary = shared.issue({"action": "place", "kind": "belt", "cell": [0, 0]})
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
	shared.issue({"action": "place", "kind": "belt", "cell": [1, 0]})
	verify(shared.construction_audio.heard.size() == 1, "The disconnected shared path stays silent.")
	shared.free()

func check_samples() -> void:
	for cue in ["belt_snap", "assembly", "coupling", "release"]:
		var stream: AudioStreamWAV = Audio.make_stream(cue)
		verify(stream == Audio.make_stream(cue) and stream.mix_rate == 44100
			and not stream.stereo and stream.format == AudioStreamWAV.FORMAT_16_BITS
			and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Original short sound resources are shared and never loop.")
		var data := stream.data
		var peak := 0.0
		var energy := 0.0
		for offset in range(0, data.size(), 2):
			var value := float(data.decode_s16(offset)) / 32768.0
			peak = maxf(peak, absf(value))
			energy += value * value
		var rms := sqrt(energy / float(data.size() / 2))
		verify(stream.get_length() >= 0.15 and stream.get_length() <= 0.43 and peak < 0.8 and rms > 0.005,
			"Each authored cue has finite duration, audible signal energy and digital headroom.")
		verify(data.decode_s16(0) == 0 and data.decode_s16(data.size() - 2) == 0,
			"Authored cues start and end at zero to avoid a hard boundary click.")
		if not preview_directory.is_empty():
			var target := preview_directory.path_join(cue + ".wav")
			verify(not FileAccess.file_exists(target) and stream.save_to_wav(target) == OK,
				"Retain each original cue for later human listening without replacing an artifact.")
		samples.append({"cue": cue, "bytes": data.size(), "seconds": stream.get_length(), "peak": peak, "rms": rms})
	verify(Audio.make_stream("unrecognized") == null, "Unknown events cannot invent an audio asset.")

func run() -> void:
	if not preview_directory.is_empty():
		if not preview_directory.is_absolute_path() or preview_directory.begins_with(ProjectSettings.globalize_path("res://")):
			verify(false, "Preview output must be an explicit external artifact directory.")
			quit(1)
			return
		DirAccess.make_dir_recursive_absolute(preview_directory)
	check_guards()
	check_actual_hooks()
	check_samples()
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks, "samples": samples,
		"scope": "invented confirmation guards, actual view callbacks and original PCM assets",
		"native_decisions": "not_run", "audible_quality": "not_assessed", "desktop": "not_used"}))
	quit(1 if failed else 0)
