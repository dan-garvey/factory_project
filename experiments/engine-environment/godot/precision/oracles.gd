extends RefCounted
## Test-only literal witnesses; no authority instance or simulation lives here.
const CASES = {
	"exact": {"input": {"A": 2, "B": 1, "X": 0}, "condition": "ready", "fix": [],
		"source_after": {"A": 6, "B": 3, "X": 1}, "returns_after": {"A": 0, "B": 0, "X": 0}, "reject_X": 0},
	"missing": {"input": {"A": 2, "B": 0, "X": 0}, "condition": "missing", "fix": [{"action": "insert", "kind": "B"}],
		"source_after": {"A": 6, "B": 3, "X": 1}, "returns_after": {"A": 0, "B": 0, "X": 0}, "reject_X": 0},
	"insufficient": {"input": {"A": 1, "B": 1, "X": 0}, "condition": "insufficient", "fix": [{"action": "insert", "kind": "A"}],
		"source_after": {"A": 6, "B": 3, "X": 1}, "returns_after": {"A": 0, "B": 0, "X": 0}, "reject_X": 0},
	"surplus": {"input": {"A": 3, "B": 1, "X": 0}, "condition": "surplus", "fix": [{"action": "recover", "kind": "A"}],
		"source_after": {"A": 5, "B": 3, "X": 1}, "returns_after": {"A": 1, "B": 0, "X": 0}, "reject_X": 0},
	"unlisted": {"input": {"A": 2, "B": 1, "X": 1}, "condition": "wrong_material", "fix": [{"action": "recover", "kind": "X"}],
		"source_after": {"A": 6, "B": 3, "X": 0}, "returns_after": {"A": 0, "B": 0, "X": 0}, "reject_X": 1},
	"substitution": {"input": {"A": 1, "B": 1, "X": 1}, "condition": "wrong_material",
		"fix": [{"action": "recover", "kind": "X"}, {"action": "insert", "kind": "A"}],
		"source_after": {"A": 6, "B": 3, "X": 0}, "returns_after": {"A": 0, "B": 0, "X": 0}, "reject_X": 1}}
var checks := 0
var failures: Array[String] = []

func expect(value: bool, label: String) -> bool:
	checks += 1
	if not value: failures.append(label)
	return value

func inspect(state: Dictionary, label: String) -> bool:
	# RefCounted ObjectIDs are opaque signed handles, not positive quantities.
	expect(state.schema is int and state.schema == 1 and state.owner is int and state.owner != 0, label + ": actual owner/schema")
	expect(state.initial == {"A": 8, "B": 4, "X": 1}, label + ": declared finite inputs")
	for field in ["output", "output_job", "finished", "current_job", "next_job", "remaining", "order", "revision", "ticks"]:
		expect(state[field] is int and state[field] >= 0, label + ": typed counter " + field)
	var totals := {"A": 0, "B": 0, "X": 0}
	for location in ["source", "input", "held", "returns", "reject"]:
		var stock: Dictionary = state.locations[location]
		var keys: Array = stock.keys()
		keys.sort()
		expect(keys == ["A", "B", "X"], label + ": material identity at " + location)
		for kind in ["A", "B", "X"]:
			expect(stock[kind] is int and stock[kind] >= 0, label + ": raw integer " + location + "/" + kind)
			totals[kind] += stock[kind]
	# Product-equivalent accounting is an independent literal, not Core.BILL.
	totals.A += 2 * (state.output + state.finished)
	totals.B += state.output + state.finished
	expect(totals == {"A": 8, "B": 4, "X": 1}, label + ": per-kind conserved locations + product equivalents")
	expect(state.output in [0, 1] and state.output == (1 if state.output_job > 0 else 0), label + ": actual output slot")
	expect(state.finished == state.finished_jobs.size(), label + ": collected product identities")
	var identities: Array = state.finished_jobs.duplicate()
	if state.output_job > 0: identities.append(state.output_job)
	if state.current_job > 0:
		identities.append(state.current_job)
		expect(state.locations.held == {"A": 2, "B": 1, "X": 0} and state.remaining <= 2, label + ": exact captured phase")
	else:
		expect(state.locations.held == {"A": 0, "B": 0, "X": 0} and state.remaining == 0, label + ": empty phase")
	identities.sort()
	expect(identities.size() == state.next_job - 1, label + ": every started job still has one holder")
	for index in identities.size():
		expect(identities[index] is int and identities[index] == index + 1, label + ": no lost/duplicate/retargeted job")
	var rows: Array = state.wiring.keys()
	rows.sort()
	expect(rows == ["feed_A", "feed_B", "reject_X", "return_extra_A", "return_extra_B", "take_output"], label + ": explicit circuit rows")
	for row in rows: expect(state.wiring[row] is bool, label + ": circuit bit " + row)
	expect(state.powered is bool, label + ": power bit")
	return failures.is_empty()

func blocked(state: Dictionary, name: String) -> bool:
	var spec: Dictionary = CASES[name]
	return expect(state.locations.input == spec.input and state.condition == spec.condition
		and state.output == 0 and state.finished == 0 and state.current_job == 0
		and state.next_job == 1 and state.remaining == 0, name + ": whole declared chamber before start/output")

func corrected(state: Dictionary, name: String) -> bool:
	var spec: Dictionary = CASES[name]
	return expect(state.locations.input == {"A": 2, "B": 1, "X": 0}
		and state.locations.source == spec.source_after and state.locations.returns == spec.returns_after
		and state.locations.reject == {"A": 0, "B": 0, "X": spec.reject_X}
		and state.condition == "ready", name + ": actual accounted correction, no reset/replacement")

func one_product(state: Dictionary, name: String) -> bool:
	var spec: Dictionary = CASES[name]
	return expect(state.output == 1 and state.output_job == 1 and state.finished == 0
		and state.current_job == 0 and state.next_job == 2 and state.remaining == 0
		and state.locations.input == {"A": 0, "B": 0, "X": 0}
		and state.locations.source == spec.source_after and state.locations.returns == spec.returns_after
		and state.locations.reject.X == spec.reject_X, name + ": one genuine completed recipe")

func all_products(state: Dictionary, name: String) -> bool:
	var rejected: int = CASES[name].reject_X
	expect(state.finished == 4 and state.finished_jobs == [1, 2, 3, 4] and state.output == 0
		and state.output_job == 0 and state.current_job == 0 and state.next_job == 5 and state.remaining == 0,
		name + ": exactly four finite products with stable identities")
	for location in ["input", "held", "returns"]:
		expect(state.locations[location] == {"A": 0, "B": 0, "X": 0}, name + ": emptied " + location)
	expect(state.locations.source == {"A": 0, "B": 0, "X": 1 - rejected}
		and state.locations.reject == {"A": 0, "B": 0, "X": rejected}, name + ": X remains at actual source/reject holder")
	return failures.is_empty()

static func physical(state: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for field in ["locations", "output", "output_job", "finished", "finished_jobs", "current_job", "next_job", "remaining"]:
		result[field] = state[field]
	return result.duplicate(true)

static func publish(path: String, value: Dictionary) -> bool:
	if not path.is_absolute_path() or not DirAccess.dir_exists_absolute(path.get_base_dir()): return false
	for target in [path, path + ".writing"]:
		if FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(target): return false
	var file := FileAccess.open(path + ".writing", FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(value))
	file.close()
	return DirAccess.rename_absolute(path + ".writing", path) == OK
