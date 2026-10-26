extends AudioStreamPlayer
## Local acknowledgement only. No command, stock or simulation authority.
signal cue_emitted(cue: String, identity: Array)
const ROOT := "res://opening/assets/construction-audio"
const FILES := {"belt_snap": "belt_snap.wav", "assembly": "assembly.wav",
	"coupling": "coupling.wav", "release": "release.wav"}
static var streams: Dictionary = {}
static var source_status := "uninitialized"
var current_context := ""
var heard: Dictionary = {}

func _init() -> void:
	volume_db = -13.0
	max_polyphony = 3

static func cue_for(action: Dictionary) -> String:
	match action.get("action", ""):
		"place":
			if action.get("kind") == "belt":
				return "belt_snap"
			if action.get("kind") in ["collector", "processor", "wheel"]:
				return "assembly"
		"place_belt_span", "place_selected_belt_span":
			return "belt_snap"
		"place_foundation", "place_foundations", "place_component", "deploy_fabrication_hub", \
		"craft_component", "field_craft", "craft_part":
			return "assembly"
		"turn_press_crank":
			return "assembly"
		"place_gear", "place_shaft", "place_relay", "shaft_between", "connect_drive", "connect":
			return "coupling"
		"remove", "remove_belt_span", "remove_shaft_between", "remove_foundation", \
		"reclaim_component", "stow_fabrication_hub", "disconnect_drive", "disconnect":
			return "release"
	return ""

static func read_samples(directory: String = ROOT) -> Dictionary:
	var present := 0
	for file in FILES.values():
		if FileAccess.file_exists(directory.path_join(file)):
			present += 1
	if present == 0:
		return {"status": "missing", "streams": {}}
	if present != FILES.size():
		return {"status": "invalid", "reason": "incomplete_cues", "streams": {}}
	var loaded: Dictionary = {}
	for cue in FILES:
		var path := directory.path_join(FILES[cue])
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return {"status": "invalid", "reason": "unreadable_" + cue, "streams": {}}
		var size := file.get_length()
		file.close()
		# Fixed local PCM clips, not arbitrary or unbounded user audio.
		if size < 44 or size > 65536:
			return {"status": "invalid", "reason": "cue_size_" + cue, "streams": {}}
		var sample := AudioStreamWAV.load_from_file(path)
		if sample == null or sample.stereo or sample.mix_rate != 44100 or sample.format != AudioStreamWAV.FORMAT_16_BITS \
				or sample.loop_mode != AudioStreamWAV.LOOP_DISABLED or sample.get_length() < 0.1 or sample.get_length() > 0.5:
			return {"status": "invalid", "reason": "cue_format_" + cue, "streams": {}}
		loaded[cue] = sample
	return {"status": "ready", "streams": loaded}

static func make_stream(cue: String) -> AudioStreamWAV:
	if not FILES.has(cue):
		return null
	if streams.has(cue):
		return streams[cue]
	if source_status == "uninitialized":
		var loaded := read_samples()
		source_status = loaded.status
		if source_status == "ready":
			streams = loaded.streams
		elif source_status == "invalid":
			push_error("Invalid construction samples: " + str(loaded.reason))
	if source_status == "ready":
		return streams[cue]
	if source_status != "missing":
		return null
	# Historical fixed-roster captures retain their original generated cue.
	var rate := 44100
	var duration: float = {"belt_snap": 0.24, "assembly": 0.42, "coupling": 0.18, "release": 0.16}[cue]
	var count := roundi(duration * rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var random := RandomNumberGenerator.new()
	random.seed = {"belt_snap": 1627, "assembly": 3471, "coupling": 619, "release": 937}[cue]
	var low_noise := 0.0
	for n in range(count):
		var t := float(n) / float(rate)
		var noise := random.randf_range(-1, 1)
		low_noise = lerpf(low_noise, noise, 0.18)
		var sample := 0.0
		match cue:
			"belt_snap":
				sample = 0.22 * sin(TAU * 155.0 * t) * exp(-22.0 * t)
				sample += 0.19 * sin(TAU * (720.0 - 500.0 * t) * t) * exp(-46.0 * t)
				sample += 0.25 * (noise - low_noise) * exp(-110.0 * t)
				if t > 0.045:
					var latch := t - 0.045
					sample += 0.19 * sin(TAU * 1850.0 * latch) * exp(-65.0 * latch)
			"assembly":
				for mode in [[140.0, 0.22, 14.0], [480.0, 0.18, 23.0], [913.0, 0.1, 27.0], [1810.0, 0.06, 36.0]]:
					sample += mode[1] * sin(TAU * mode[0] * t) * exp(-mode[2] * t)
				sample += 0.18 * low_noise * exp(-30.0 * t)
			"coupling":
				sample = 0.23 * sin(TAU * 950.0 * t) * exp(-52.0 * t)
				sample += 0.13 * sin(TAU * 2410.0 * t) * exp(-65.0 * t)
				sample += 0.2 * (noise - low_noise) * exp(-95.0 * t)
			"release":
				sample = 0.2 * sin(TAU * (1500.0 - 2400.0 * t) * t) * exp(-48.0 * t)
				sample += 0.22 * low_noise * exp(-35.0 * t)
		var envelope := minf(1.0, t / 0.002) * clampf((duration - t) / 0.03, 0.0, 1.0)
		sample = 0.85 * sample * envelope if n > 0 and n < count - 1 else 0.0
		bytes.encode_s16(n * 2, clampi(roundi(sample * 32767.0), -32767, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = bytes
	streams[cue] = stream
	return stream

func confirmed(action: Dictionary, outcome: Dictionary, live_context: String) -> bool:
	var cue := cue_for(action)
	if cue.is_empty() or typeof(outcome.get("accepted")) != TYPE_BOOL or not outcome.accepted:
		return false
	for flag in ["queued", "duplicate"]:
		if typeof(outcome.get(flag, false)) != TYPE_BOOL or outcome.get(flag, false):
			return false
	var identity: Array[String] = []
	for field in ["context", "client", "request"]:
		if typeof(action.get(field)) != TYPE_STRING or action[field].is_empty() or outcome.get(field) != action[field]:
			return false
		identity.append(action[field])
	if live_context.is_empty() or identity[0] != live_context:
		return false
	if current_context != live_context:
		current_context = live_context
		heard.clear()
	var key := JSON.stringify(identity)
	if heard.has(key):
		return false
	var next_stream := make_stream(cue)
	if next_stream == null:
		return false
	heard[key] = true
	stream = next_stream
	play()
	cue_emitted.emit(cue, identity)
	return true
