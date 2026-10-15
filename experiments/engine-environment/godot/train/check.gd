extends "res://rider/check.gd"
## Actual input crosses two separate native support bodies on one fixed path.

func _scene_path() -> String:
	return "res://train/main.tscn"

func facts() -> Dictionary:
	var value: Dictionary = super.facts()
	value["trailing_mesh"] = array(scene.trailing_mesh.position)
	value["trailing_visible"] = scene.trailing_mesh.visible
	return value

func check_deck_pose(value: Dictionary, at_advance: bool) -> void:
	super.check_deck_pose(value, at_advance)
	var expected := 3 + 2 * sin(float(value.state.phases.U))
	check(absf(value.auxiliary.position[0] - expected) < 0.00002
		and absf(value.auxiliary.position[0] - value.deck.position[0] - 3) < 0.00002,
		"Both actual native carriages reach their common phase-owned coupled goal")
	if at_advance:
		check(absf(value.state.completed.positions.U[0] - expected) < 0.00002
			and absf(value.trailing_mesh[0] - expected) < 0.00002,
			"Exact Drive event publishes and displays both actual native carriages")

func standing(branch: String, relative: float) -> void:
	var value := facts()
	var body: Dictionary = value.deck if branch == "B" else value.auxiliary
	check(value.on_floor and value.floor_id == body.id and absf(value.player.position[0] - body.position[0] - relative) <= 0.015,
		"Actual native carriage retains the standing rider through the fixed cycle")

func _run() -> void:
	start_observers()
	await fresh()
	cases.initial = facts()
	await board()
	cases.boarded = facts()
	var front_relative: float = scene.player.position.x - scene.authority.bodies.B.position.x
	stage = "front_standing"
	await click(scene.run_button)
	for index in range(8):
		await step(index == 0)
		standing("B", front_relative)
	cases.front_end = facts()
	stage = "crossing"
	cases.cross_before = facts()
	await click(scene.repeat_button)
	await hold(KEY_D, true)
	for index in range(180):
		if scene.player.floor_id == scene.authority.bodies.U.get_instance_id() \
			and scene.player.position.x - scene.authority.bodies.U.position.x >= -0.4:
			break
		await ticks(1)
	await hold(KEY_D, false)
	await click(scene.repeat_button)
	for index in range(4):
		if not scene.authority.pending:
			break
		await ticks(1)
	await ticks(4)
	cases.cross_after = facts()
	check(scene.player.floor_id == scene.authority.bodies.U.get_instance_id() and not scene.authority.pending
		and scene.authority.committed > 8 and scene.authority.committed < 24,
		"Actual D input crosses the moving joint from B to U while real repeat drives both bodies")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--capture="):
				check(root.get_texture().get_image().save_png(argument.trim_prefix("--capture=")) == OK,
					"Actual viewport captures the rider after its native support changes to carriage U")
	var rear_relative: float = scene.player.position.x - scene.authority.bodies.U.position.x
	stage = "rear_standing"
	while scene.authority.committed < 24:
		await step()
		standing("U", rear_relative)
	cases.rear_end = facts()
	while scene.authority.committed < 32:
		await step()
		standing("U", rear_relative)
	cases.home = facts()
	await click(scene.run_button)
	stage = "jump"
	await key(KEY_SPACE)
	await ticks(12)
	cases.air = facts()
	check(not scene.player.is_on_floor() and scene.player.position.y > 2.5, "Actual independent player jumps from the stopped rear carriage")
	for index in range(100):
		if scene.player.is_on_floor():
			break
		await ticks(1)
	cases.landed = facts()
	check(scene.player.floor_id == scene.authority.bodies.U.get_instance_id(), "Native gravity lands the same player on carriage U")
	stage = "step_off"
	await hold(KEY_D, true)
	for index in range(180):
		if scene.player.is_on_floor() and scene.player.floor_id == scene.ground.get_instance_id():
			break
		await ticks(1)
	await hold(KEY_D, false)
	await ticks(4)
	cases.off = facts()
	check(scene.player.floor_id == scene.ground.get_instance_id(), "Ordinary walking leaves the two-car assembly onto fixed ground")
	stage = "wall"
	await hold(KEY_D, true)
	await ticks(140)
	await hold(KEY_D, false)
	await ticks(4)
	cases.wall = facts()
	check(absf(scene.player.position.x - 8.575) < 0.015, "Actual player collides with the fixed wall beyond the whole carriage envelope")
	capturing = false
	finish_requested = true
