extends "res://rider/check.gd"
## The same actual controller and native epoch collector, with rotary oracles.
var seed := Vector3.ZERO

func _scene_path() -> String:
	return "res://rotary/main.tscn"

func basis_of(axes: Array) -> Basis:
	return Basis(Vector3(axes[0][0], axes[0][1], axes[0][2]), Vector3(axes[1][0], axes[1][1], axes[1][2]),
		Vector3(axes[2][0], axes[2][1], axes[2][2]))

func local_player(value: Dictionary) -> Vector3:
	var body: Array = value.deck.position
	var player: Array = value.player.position
	return basis_of(value.deck.basis).inverse() * (Vector3(player[0], player[1], player[2]) - Vector3(body[0], body[1], body[2]))

func check_deck_pose(value: Dictionary, at_advance: bool) -> void:
	var expected := Basis(Vector3.UP, value.state.phases.B)
	var actual := basis_of(value.deck.basis)
	check(Vector3(value.deck.position[0], value.deck.position[1], value.deck.position[2]).distance_to(Vector3(0, 0.75, 0)) < 0.00002
		and actual.x.distance_to(expected.x) < 0.00002 and actual.z.distance_to(expected.z) < 0.00002,
		"Native rotary goal basis and fixed centre match signed inherited phase")
	if at_advance:
		var completed := basis_of(value.state.completed.basis)
		var mesh := basis_of(value.deck_mesh_basis)
		check(completed.x.distance_to(actual.x) < 0.00002 and completed.z.distance_to(actual.z) < 0.00002
			and mesh.x.distance_to(actual.x) < 0.00002 and mesh.z.distance_to(actual.z) < 0.00002,
			"Exact Drive event publishes and displays actual native rotary basis")

func standing() -> void:
	var value := facts()
	check(value.on_floor and value.floor_id == value.deck.id and local_player(value).distance_to(seed) <= 0.015,
		"Off-axis native rider retains local standing pose without parenting or compensation")

func _run() -> void:
	start_observers()
	await fresh()
	cases.initial = facts()
	await board()
	cases.boarded = facts()
	seed = local_player(cases.boarded)
	check(Vector2(seed.x, seed.z).length() >= 0.3 and Vector2(seed.x, seed.z).length() <= 0.5,
		"Real boarding gives a nonzero off-axis witness, never a centred dummy")
	stage = "standing_positive"
	await click(scene.run_button)
	for index in range(8):
		await step(index == 0)
		standing()
	cases.positive8 = facts()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--capture="):
				check(root.get_texture().get_image().save_png(argument.trim_prefix("--capture=")) == OK, "Actual off-axis rotary passenger viewport capture")
	for index in range(24):
		await step()
		standing()
	cases.positive32 = facts()
	check(absf(scene.authority.phases.B - TAU) < 0.00002, "Thirty-two inherited positive goals give a full unwrapped turn")
	stage = "walk_turn"
	var before_walk := facts()
	await hold(KEY_D, true)
	await step()
	await hold(KEY_D, false)
	await ticks(4)
	cases.walk = {"before": before_walk, "after": facts()}
	check(scene.player.is_on_floor() and scene.player.floor_id == scene.authority.bodies.B.get_instance_id(),
		"Ordinary walking remains supported while actual native deck turns")
	stage = "jump_turn"
	# Source input and player input are both real; the native goal owns itself
	# while the independent character can jump and land.
	await key(KEY_N)
	await key(KEY_SPACE)
	await ticks(12)
	cases.air = facts()
	check(not scene.player.is_on_floor() and scene.player.position.y > 2.5, "Actual jump is independent during a pending rotary goal")
	for index in range(120):
		if scene.player.is_on_floor() and not scene.authority.pending:
			break
		await ticks(1)
	cases.landed = facts()
	check(not scene.authority.pending, "Owned rotary jump goal reaches native completion before the next stage")
	check(scene.player.floor_id == scene.authority.bodies.B.get_instance_id(), "Actual native player lands on same turned deck")
	await click(scene.run_button)
	stage = "step_off"
	await hold(KEY_D, true)
	for index in range(180):
		if scene.player.is_on_floor() and scene.player.floor_id == scene.ground.get_instance_id():
			break
		await ticks(1)
	await hold(KEY_D, false)
	await ticks(4)
	cases.off = facts()
	check(scene.player.floor_id == scene.ground.get_instance_id(), "Real input leaves rotated deck onto fixed ground")
	stage = "wall"
	await hold(KEY_D, true)
	await ticks(100)
	await hold(KEY_D, false)
	await ticks(4)
	cases.wall = facts()
	check(absf(scene.player.position.x - 4.575) < 0.015, "Native player still meets fixed solid boundary after rotary ride")

	await fresh()
	await board()
	# Explicit initial fixture API control, not a player construction claim.
	scene.authority.idler = false
	await ticks(3)
	cases.negative_seed = facts()
	seed = local_player(cases.negative_seed)
	stage = "standing_negative"
	await key(KEY_F)
	for index in range(8):
		await step()
		standing()
	cases.negative8 = facts()
	check(absf(scene.authority.phases.B + PI / 2) < 0.00002, "Same signed owner drives the real reversed quarter-turn")
	await click(scene.run_button)
	await fresh()
	await board()
	# Same native follow-filter control used in the accepted linear probe.
	scene.player.platform_floor_layers = 0
	await ticks(3)
	cases.disabled_before = facts()
	stage = "follow_disabled"
	await key(KEY_F)
	await step()
	cases.disabled_after = facts()
	check(Vector3(cases.disabled_after.player.position[0], cases.disabled_after.player.position[1], cases.disabled_after.player.position[2]).distance_to(
		Vector3(cases.disabled_before.player.position[0], cases.disabled_before.player.position[1], cases.disabled_before.player.position[2])) < 0.015,
		"Without native following the same rider stays put while the physical deck rotates")
	capturing = false
	finish_requested = true
