extends "res://rider/startup_observer.gd"

func _scene_path() -> String:
	return "res://train/main.tscn"

func _finish(report: Dictionary) -> void:
	var scene = get_tree().current_scene
	report["carriages"] = {}
	for branch in ["B", "U"]:
		var body: PhysicsBody3D = scene.authority.bodies[branch]
		var pose: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		var mesh: MeshInstance3D = scene.deck_mesh if branch == "B" else scene.trailing_mesh
		var expected := Vector3(0 if branch == "B" else 3, 0.75, 0)
		var published: Array = report.state.completed.get("positions", {}).get(branch, [])
		report.carriages[branch] = {"id": body.get_instance_id(), "rid": body.get_rid().get_id(),
			"native": [pose.origin.x, pose.origin.y, pose.origin.z], "mesh": [mesh.position.x, mesh.position.y, mesh.position.z]}
		if published.size() != 3 or pose.origin.distance_to(expected) > 0.00002 or mesh.position.distance_to(expected) > 0.00002:
			report.status = "fail"
		elif Vector3(published[0], published[1], published[2]).distance_to(expected) > 0.00002:
			report.status = "fail"
	await super._finish(report)
