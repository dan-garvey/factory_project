extends Node3D
const Geometry = preload("res://opening/site_geometry.gd")

## Disposable audio from confirmed motion, never a simulation clock.
const SOURCE_AUDIBLE_RADIUS := 16.0
static var loops: Dictionary = {}
var emitters: Dictionary = {}
var listener: AudioListener3D
var context := ""
var scanned_entities: Dictionary = {}
var scanned_motions: Dictionary = {}
var scanned_listener_position := Vector3.ZERO
var scanned_revision := -1
var scanned_order := -1
var source_scan_ready := false
var scanned_native_revision := false

func _init() -> void:
	listener = AudioListener3D.new()
	listener.name = "WorkerAudioListener"
	add_child(listener)

static func make_loop(kind: String) -> AudioStreamWAV:
	if kind not in ["collector", "belt", "processor", "wheel"]:
		return null
	if loops.has(kind):
		return loops[kind]
	var cycles: int = {"collector": 190, "belt": 124, "processor": 98, "wheel": 76}[kind]
	var random := RandomNumberGenerator.new()
	random.seed = {"collector": 3461, "belt": 6127, "processor": 1987, "wheel": 4231}[kind]
	var partials: Array = []
	for n in range(24):
		partials.append([random.randi_range(180, 5200), random.randf_range(0, TAU)])
	var count := 88200
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for n in range(count):
		var phase := float(n) / count
		# Every component has an integer number of cycles in this two-second
		# loop. Its seam is continuous; it does not claim a physical phase.
		var tone := 0.11 * sin(TAU * cycles * phase) + 0.035 * sin(TAU * cycles * 2 * phase)
		var grain := 0.0
		for partial in partials:
			grain += sin(TAU * int(partial[0]) * phase + float(partial[1])) * 0.0025
		var envelope := 0.78 + 0.22 * cos(TAU * phase * 3.0)
		var sample := clampf((tone + grain) * envelope, -0.25, 0.25)
		bytes.encode_s16(n * 2, roundi(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 44100
	stream.stereo = false
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	loops[kind] = stream
	return stream

static func _numeric(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))

static func _pose(value: Variant) -> bool:
	return value is Array and value.size() == 3 and _numeric(value[0]) and _numeric(value[1]) and _numeric(value[2])

static func _rotating(value: Variant) -> bool:
	return value is Dictionary and value.get("state") == "rotating" and typeof(value.get("numerator")) == TYPE_INT \
		and typeof(value.get("denominator")) == TYPE_INT and value.denominator > 0 and value.numerator != 0

func silence() -> void:
	for emitter in emitters.values():
		emitter.stop()
		emitter.free()
	emitters.clear()
	if is_inside_tree() and listener.is_current():
		listener.clear_current()
	context = ""
	scanned_entities = {}
	scanned_motions = {}
	scanned_revision = -1
	scanned_order = -1
	source_scan_ready = false
	scanned_native_revision = false

func sync(snapshot: Dictionary, actor: String, ready: bool, camera_basis: Basis,
		trusted_native_revision := false) -> void:
	var options: Variant = snapshot.get("options")
	var actors: Variant = snapshot.get("actors")
	var body: Variant = actors.get(actor) if actors is Dictionary else null
	var entities: Variant = snapshot.get("entities")
	var motions: Variant = snapshot.get("motion")
	var world: Variant = snapshot.get("context")
	if not ready or not is_inside_tree() or not options is Dictionary or typeof(options.get("native")) != TYPE_BOOL \
		or not options.native or not body is Dictionary or typeof(body.get("ready")) != TYPE_BOOL or not body.ready \
		or not _pose(body.get("position")) or not entities is Dictionary or not motions is Dictionary \
		or typeof(world) != TYPE_STRING or world.is_empty() or not camera_basis.is_finite() or absf(camera_basis.determinant()) < 0.5:
		silence()
		return
	if world != context:
		silence()
		context = world
	# Body origin plus a presentation-only ear offset. Camera distance cannot
	# move the listener away from the worker or grant construction reach.
	listener.position = Vector3(body.position[0], body.position[1], body.position[2]) + Vector3.UP * 0.55
	listener.basis = camera_basis.orthonormalized()
	if not listener.is_current():
		listener.make_current()
	# Native World revisions cover source state changes even when a new
	# projection allocates fresh dictionaries for an unchanged tick. Other
	# callers retain the identity check for same-version replacements.
	# Physical ear movement still rescans; camera rotation always reaches it.
	var revision: Variant = snapshot.get("revision")
	var order: Variant = snapshot.get("order")
	var versioned := typeof(revision) == TYPE_INT and typeof(order) == TYPE_INT
	if versioned and source_scan_ready and revision == scanned_revision and order == scanned_order \
			and ((trusted_native_revision and scanned_native_revision) \
				or (is_same(entities, scanned_entities) and is_same(motions, scanned_motions))) \
			and listener.position == scanned_listener_position:
		return
	scanned_entities = entities
	scanned_motions = motions
	scanned_listener_position = listener.position
	scanned_revision = int(revision) if versioned else -1
	scanned_order = int(order) if versioned else -1
	source_scan_ready = versioned
	scanned_native_revision = versioned and trusted_native_revision
	var audible: Dictionary = {}
	for id: Variant in entities:
		var entity: Variant = entities[id]
		var motion: Variant = motions.get(id)
		if typeof(id) != TYPE_STRING or not entity is Dictionary or not _rotating(motion):
			continue
		var kind: Variant = entity.get("kind")
		var cell: Variant = entity.get("cell")
		if typeof(kind) != TYPE_STRING or kind not in ["collector", "belt", "processor", "wheel"] \
			or not cell is Array or cell.size() != 2 or typeof(cell[0]) != TYPE_INT or typeof(cell[1]) != TYPE_INT:
			continue
		var source_position := Vector3(cell[0] * Geometry.PITCH, 0.7, cell[1] * Geometry.PITCH)
		if not source_position.is_finite() or listener.position.distance_squared_to(source_position) \
				> SOURCE_AUDIBLE_RADIUS * SOURCE_AUDIBLE_RADIUS:
			continue
		audible[id] = true
		if emitters.has(id) and emitters[id].get_meta("kind") != kind:
			emitters[id].stop()
			emitters[id].free()
			emitters.erase(id)
		if not emitters.has(id):
			var emitter := AudioStreamPlayer3D.new()
			emitter.set_meta("entity", id)
			emitter.set_meta("kind", kind)
			emitter.stream = make_loop(kind)
			emitter.volume_db = -23.0
			emitter.max_db = -14.0
			emitter.unit_size = 2.5
			emitter.max_distance = SOURCE_AUDIBLE_RADIUS
			emitter.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
			emitter.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
			add_child(emitter)
			emitters[id] = emitter
		# A bounded timbre change, not a rate clamp in the native mechanics.
		emitters[id].pitch_scale = clampf(absf(float(motion.numerator) / float(motion.denominator)), 0.6, 1.8)
		emitters[id].position = source_position
		if not emitters[id].playing:
			emitters[id].play()
	for id in emitters.keys():
		if not audible.has(id):
			emitters[id].stop()
			emitters[id].free()
			emitters.erase(id)
