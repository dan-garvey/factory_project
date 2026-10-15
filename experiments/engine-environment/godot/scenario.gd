extends RefCounted
## Shared command schedule, not a second rules implementation or test oracle.

static func build(send: Callable):
	for row in [["collector", [0, 0]], ["belt", [1, 0]], ["processor", [2, 0]]]:
		send.call({"action": "place", "kind": row[0], "cell": row[1]})
	for pair in [["collector-1", "belt-1"], ["belt-1", "processor-1"]]:
		send.call({"action": "connect", "from": pair[0], "to": pair[1]})

static func finish(model, send: Callable):
	for _tick in range(32):
		if model.projection().stock.output > 0:
			send.call({"action": "retrieve", "amount": 1})
		model.advance()
	if model.projection().stock.output > 0:
		send.call({"action": "retrieve", "amount": 1})

static func conserved(state: Dictionary) -> bool:
	var s: Dictionary = state.stock
	var raw: int = s.source + s.collector + s.belt + s.input + s.held
	return raw + state.recipe_input * (s.output + s.player) == state.initial_feed
