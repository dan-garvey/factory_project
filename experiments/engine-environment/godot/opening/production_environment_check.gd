extends SceneTree
## Isolated visual resources and world assembly. No gameplay or desktop input.
const Opening = preload("res://opening/opening.gd")
const Geometry = preload("res://opening/site_geometry.gd")
const Scenery = Opening.ProductionEnvironment
var checks := 0
var failed := false
var mode := "environment"

class FixtureView:
	extends "res://opening/opening.gd"
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)

func inspect_visual(node: Node) -> void:
	verify(not node is CollisionObject3D and not node is CollisionShape3D,
		"Scenery must not introduce physical or pick authority.")
	verify(node.get_script() == null, "Scenery has no independent controller or clock.")
	for child in node.get_children():
		inspect_visual(child)

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--environment-case="):
			mode = argument.trim_prefix("--environment-case=")
	call_deferred("run")

func check_foliage(foliage: MultiMesh) -> void:
	# The dummy renderer preserves bulk uploads but ignores per-instance getters.
	# Inspect the actual retained buffer, not a separately recomputed layout.
	var buffer := foliage.buffer
	verify(buffer.size() == foliage.instance_count * 16,
		"The actual foliage buffer contains each complete matrix and color.")
	if buffer.size() != foliage.instance_count * 16:
		return
	for n in range(foliage.instance_count):
		var offset := n * 16
		var origin := Vector3(buffer[offset + 3], buffer[offset + 7], buffer[offset + 11])
		var basis := Basis(Vector3(buffer[offset], buffer[offset + 4], buffer[offset + 8]),
			Vector3(buffer[offset + 1], buffer[offset + 5], buffer[offset + 9]),
			Vector3(buffer[offset + 2], buffer[offset + 6], buffer[offset + 10]))
		verify(origin.is_finite() and basis.is_finite() and basis.determinant() > 0.2
			and is_equal_approx(origin.y, Geometry.GROUND_HEIGHT)
			and (absf(origin.x - 1.65) > 6.9 or absf(origin.z - 1.65) > 6.9),
			"Low decorative foliage stays outside the construction pad and introduces no solid obstacle.")
		for channel in range(4):
			verify(is_finite(buffer[offset + 12 + channel]) and buffer[offset + 12 + channel] >= 0
				and buffer[offset + 12 + channel] <= 1, "Each uploaded color channel is finite and bounded.")

func finish() -> void:
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks, "mode": mode,
		"scope": "visual assembly and resources" if mode == "environment" else "changed foliage bulk upload",
		"rendered_quality": "not_assessed", "desktop": "not_used", "authority_started": false}))
	quit(1 if failed else 0)

func run() -> void:
	if mode == "foliage":
		var node := Scenery._foliage()
		inspect_visual(node)
		check_foliage(node.multimesh)
		node.free()
		finish()
		return
	if mode != "environment":
		verify(false, "Declare an environment or changed-foliage case.")
		finish()
		return
	var view := FixtureView.new()
	root.add_child(view)
	view._build_world()
	var scenery: Node3D = view.get_node("ProductionScenery")
	inspect_visual(scenery)
	verify(view.model == null and view.actor_world == null and view.state.is_empty(),
		"The actual world-construction hunk cannot create or mutate game authority.")
	var ground: MeshInstance3D = scenery.get_node("GroundSurface")
	verify(ground.mesh is PlaneMesh and ground.mesh.size == Vector2(256, 256)
		and is_equal_approx(ground.position.y, Geometry.GROUND_HEIGHT - 0.01),
		"The visible terrain preserves the existing flat physical-floor relationship.")
	var stream: MeshInstance3D = scenery.get_node("StreamSurface")
	verify(stream.mesh is PlaneMesh and stream.mesh.size == Vector2(1.2, 13.4)
		and stream.position.is_equal_approx(Vector3(-2.7, 0.03, 1.65)),
		"The new water surface keeps the original stream footprint and top height.")
	verify(ground.material_override == Scenery.ground_material()
		and stream.material_override == Scenery.water_material(),
		"Repeated world views share the authored material resources.")
	var soil: StandardMaterial3D = ground.material_override
	verify(soil.albedo_texture is NoiseTexture2D and soil.normal_texture is NoiseTexture2D
		and soil.normal_enabled and soil.albedo_texture.seamless and soil.normal_texture.seamless,
		"The ground uses actual repeating color and normal detail.")
	var water: StandardMaterial3D = stream.material_override
	var ripples: Image = water.normal_texture.get_image()
	verify(ripples.get_width() == 128 and ripples.get_height() == 128 and ripples.has_mipmaps()
		and water.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,
		"Water uses an opaque mipmapped ripple surface without a sorting dependency.")
	for y in range(0, 128, 16):
		for x in range(0, 128, 16):
			var pixel := ripples.get_pixel(x, y)
			var normal := Vector3(pixel.r, pixel.g, pixel.b) * 2.0 - Vector3.ONE
			verify(normal.is_finite() and absf(normal.length() - 1.0) < 0.02 and normal.z > 0.9,
				"The encoded surface normals remain finite and forward-facing after eight-bit packing.")
	var environment: Environment = scenery.get_node("WorksiteEnvironment").environment
	verify(environment.sky.sky_material == Scenery.panorama_material()
		and environment.background_mode == Environment.BG_SKY
		and environment.reflected_light_source == Environment.REFLECTION_SOURCE_SKY,
		"The actual environment uses the shared original sky for background and reflections.")
	verify(environment.fog_mode == Environment.FOG_MODE_DEPTH
		and environment.fog_depth_begin > 24.0 + 6.7 * sqrt(2.0)
		and environment.fog_depth_end < view.camera.far,
		"Distance haze begins beyond the normal worksite and closes before the far clip.")
	var panorama: Image = environment.sky.sky_material.panorama.get_image()
	verify(panorama.get_width() == 512 and panorama.get_height() == 256
		and panorama.get_format() == Image.FORMAT_RGBF and panorama.has_mipmaps(),
		"The self-contained sky preserves actual HDR data and a mip chain.")
	var brightest := Vector2i.ZERO
	var energy := 0.0
	for y in range(256):
		verify(panorama.get_pixel(0, y).is_equal_approx(panorama.get_pixel(511, y)),
			"The panorama wraps without an authored longitude seam.")
		for x in range(512):
			var color := panorama.get_pixel(x, y)
			if color.r > energy:
				energy = color.r
				brightest = Vector2i(x, y)
	var latitude := PI * (0.5 - float(brightest.y) / 255.0)
	var longitude := TAU * float(brightest.x) / 511.0
	var sampled_direction := Vector3(cos(latitude) * sin(longitude), sin(latitude), -cos(latitude) * cos(longitude))
	var sun: DirectionalLight3D = scenery.get_node("WorksiteSun")
	verify(energy > 4.0 and sampled_direction.dot(sun.basis.z) > 0.999,
		"The HDR sun aligns with the actual light in the pinned SKY_COORDS convention.")
	verify(sun.shadow_enabled and sun.directional_shadow_max_distance >= environment.fog_depth_begin
		and not scenery.get_node("WorksiteFill").shadow_enabled,
		"Only the actual key light creates a worksite shadow map.")
	var foliage: MultiMesh = scenery.get_node("GroundFoliage").multimesh
	check_foliage(foliage)
	verify(not view.machine_root.get_child_count() and view.character_presenter == null,
		"The environment fixture creates neither machines nor controlled actors.")
	view.free()
	finish()
