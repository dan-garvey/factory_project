extends Node
## A short presentation score for the already deployed native landing pod.
## It reads the reveal clock and never owns pod, actor or material state.

signal cue_emitted(cue: String)

const DURATION := 2.8
const SAMPLE_RATE := 22050
const TOUCHDOWN := preload("res://opening/assets/construction-audio/assembly.wav")
const LATCH := preload("res://opening/assets/construction-audio/coupling.wav")
const EVENTS := {"touchdown": 1.45, "latch_port": 1.72,
	"latch_starboard": 2.12, "hub_ready": 2.52}
const EVENT_ORDER := ["touchdown", "latch_port", "latch_starboard", "hub_ready"]

var descent_stream: AudioStreamWAV
var ready_stream: AudioStreamWAV

var active := false
var elapsed := 0.0
var cue_history: Array[String] = []
var voices: Dictionary = {}


static func _wav(samples: PackedByteArray) -> AudioStreamWAV:
	var result := AudioStreamWAV.new()
	result.format = AudioStreamWAV.FORMAT_16_BITS
	result.mix_rate = SAMPLE_RATE
	result.stereo = false
	result.data = samples
	return result


func _descent() -> AudioStreamWAV:
	if descent_stream != null:
		return descent_stream
	var count := roundi(DURATION * SAMPLE_RATE)
	var samples := PackedByteArray()
	samples.resize(count * 2)
	var phase := 0.0
	var sub_phase := 0.0
	var filtered_noise := 0.0
	var random := RandomNumberGenerator.new()
	random.seed = 0x4d4552494449414e
	for index in count:
		var time := float(index) / SAMPLE_RATE
		var progress := time / DURATION
		var frequency := lerpf(142.0, 74.0, progress)
		phase += TAU * frequency / SAMPLE_RATE
		sub_phase += TAU * 39.0 / SAMPLE_RATE
		filtered_noise = 0.985 * filtered_noise + 0.015 * random.randf_range(-1.0, 1.0)
		var envelope := minf(1.0, time / 0.16) * minf(1.0, (DURATION - time) / 0.28)
		var engine := 0.38 * sin(phase) + 0.16 * sin(phase * 2.01) + 0.18 * sin(sub_phase)
		var sample := clampf(envelope * (engine + filtered_noise * 1.4), -0.8, 0.8)
		samples.encode_s16(index * 2, roundi(sample * 32767.0))
	descent_stream = _wav(samples)
	return descent_stream


func _ready_chime() -> AudioStreamWAV:
	if ready_stream != null:
		return ready_stream
	var count := roundi(0.58 * SAMPLE_RATE)
	var samples := PackedByteArray()
	samples.resize(count * 2)
	for index in count:
		var time := float(index) / SAMPLE_RATE
		var attack := minf(1.0, time / 0.012)
		var envelope := attack * exp(-time * 6.0) * minf(1.0, (0.58 - time) / 0.055)
		var bell := 0.48 * sin(TAU * 392.0 * time) + 0.30 * sin(TAU * 523.25 * time) \
			+ 0.12 * sin(TAU * 1046.5 * time)
		samples.encode_s16(index * 2, roundi(clampf(envelope * bell, -0.95, 0.95) * 32767.0))
	ready_stream = _wav(samples)
	return ready_stream

static func workshop_chime() -> AudioStreamWAV:
	var count := roundi(0.72 * SAMPLE_RATE)
	var samples := PackedByteArray()
	samples.resize(count * 2)
	for index in count:
		var time := float(index) / SAMPLE_RATE
		var envelope := minf(1.0, time / 0.016) * exp(-time * 4.2) \
			* minf(1.0, (0.72 - time) / 0.08)
		var bell := 0.34 * sin(TAU * 523.25 * time) \
			+ 0.26 * sin(TAU * 659.25 * time) + 0.18 * sin(TAU * 783.99 * time)
		samples.encode_s16(index * 2, roundi(clampf(envelope * bell, -0.95, 0.95) * 32767.0))
	return _wav(samples)


func _ready() -> void:
	for cue in ["descent", "touchdown", "latch_port", "latch_starboard", "hub_ready"]:
		var player := AudioStreamPlayer.new()
		player.name = cue.to_pascal_case()
		player.bus = "Master"
		player.volume_db = {"descent": -19.0, "touchdown": -11.0,
			"latch_port": -15.0, "latch_starboard": -15.0, "hub_ready": -16.0}[cue]
		player.stream = _descent() if cue == "descent" else \
			_ready_chime() if cue == "hub_ready" else \
			TOUCHDOWN if cue == "touchdown" else LATCH
		player.pitch_scale = 0.72 if cue == "touchdown" else \
			(0.93 if cue == "latch_port" else 1.06 if cue == "latch_starboard" else 1.0)
		add_child(player)
		voices[cue] = player


func _emit(cue: String) -> void:
	voices[cue].play()
	cue_history.append(cue)
	cue_emitted.emit(cue)


func begin() -> void:
	if active:
		return
	stop_all()
	active = true
	elapsed = 0.0
	cue_history.clear()
	_emit("descent")


func advance(seconds: float) -> void:
	if not active or not is_finite(seconds):
		return
	var next := clampf(seconds, elapsed, DURATION)
	for cue in EVENT_ORDER:
		if elapsed < EVENTS[cue] and next >= EVENTS[cue]:
			_emit(cue)
	elapsed = next


func finish(skipped: bool) -> void:
	if not active:
		return
	active = false
	voices.descent.stop()
	if skipped:
		stop_all()


func stop_all() -> void:
	for voice in voices.values():
		voice.stop()


func all_stopped() -> bool:
	for voice in voices.values():
		if voice.playing:
			return false
	return true


func _exit_tree() -> void:
	stop_all()
	for voice in voices.values():
		voice.stream = null
	voices.clear()
	descent_stream = null
	ready_stream = null
