extends SceneTree
## Load the actual fixed-roster view payload, without starting a game or actor.
var checks := 0
var entry := ""

func require(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		push_error(message)
		print(JSON.stringify({"status": "fail", "entry": entry, "checks": checks, "reason": message}))
		quit(1)
	return condition

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--closure-entry="):
			entry = argument.trim_prefix("--closure-entry=")
	if not require(entry in ["offline", "shared"], "Declare the captured launcher roster."):
		return
	for absent in ["production_visuals.gd", "assets/surface_height.tres",
		"assets/surface_grain.tres", "assets/surface_normal.tres"]:
		if not require(not FileAccess.file_exists("res://opening/" + absent),
			"The fixture cannot smuggle the omitted graphics files into the launcher payload."):
			return
	var path := "res://opening/opening.gd" if entry == "offline" else "res://opening/shared_opening.gd"
	var script: Script = load(path)
	if not require(script != null and script.can_instantiate(), "The actual captured view must load independently of the omitted files."):
		return
	var view: Node3D = script.new()
	var source: Script = load("res://opening/opening.gd")
	var visuals: Variant = source.ProductionVisuals
	var paint: StandardMaterial3D = visuals.material(Color("d6a34d"), 0.08, 0.5)
	var normal: NoiseTexture2D = paint.normal_texture
	var grain: NoiseTexture2D = paint.roughness_texture
	if not require(normal != null and grain != null and normal.noise == grain.noise,
		"Both surfaces must use the same original height source."):
		return
	if not require(normal.noise is FastNoiseLite and normal.noise.seed == 1627
		and is_equal_approx(normal.noise.frequency, 0.13) and normal.noise.fractal_octaves == 3,
		"Captured surfaces must preserve the authored height parameters."):
		return
	if not require(normal.width == 256 and normal.height == 256 and grain.width == 256 and grain.height == 256
		and normal.seamless and grain.seamless and normal.generate_mipmaps and grain.generate_mipmaps,
		"The captured resources must preserve dimensions, repeat and mipmap settings."):
		return
	if not require(normal.as_normal_map and not grain.as_normal_map and is_equal_approx(normal.bump_strength, 1.5)
		and grain.color_ramp != null and grain.color_ramp.colors == PackedColorArray([Color(0.72, 0.72, 0.72, 1), Color.WHITE]),
		"Normal conversion and the original roughness ramp must survive the closure correction."):
		return
	if not require(paint == visuals.material(Color("d6a34d"), 0.08, 0.5)
		and paint.normal_enabled and is_equal_approx(paint.normal_scale, 0.18)
		and paint.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC,
		"The actual captured view must retain shared, normal-mapped finishes."):
		return
	var parent := Node3D.new()
	var part: MeshInstance3D = view._machine_box(parent, "CapturedHousing", Vector3.ZERO, Vector3(0.56, 0.17, 0.55), Color("d6a34d"))
	if not require(part.material_override == paint and part.mesh is ArrayMesh and view.model == null,
		"The view must bind the self-contained finish without starting a game authority."):
		return
	parent.free()
	view.free()
	print(JSON.stringify({"status": "pass", "entry": entry, "checks": checks,
		"scope": "fixed-roster view loading and procedural surface construction",
		"scene_started": false, "desktop": "not_used", "rendered_quality": "not_assessed"}))
	quit(0)
