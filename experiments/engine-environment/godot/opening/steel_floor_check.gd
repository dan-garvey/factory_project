extends SceneTree
## Real image/material and foundation assembly checks; no game authority.
const Opening = preload("res://opening/opening.gd")
const Steel = Opening.ProductionSteelFloor

class VisualWorld extends Opening:
	func _ready() -> void:
		set_process(false)

var checks := 0
var failed := false
var controls_dir := ""
var material_only := false

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)

func channel(color: Color, selected: int) -> float:
	match selected:
		BaseMaterial3D.TEXTURE_CHANNEL_RED: return color.r
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN: return color.g
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE: return color.b
	return -1.0

func base_image(texture: Texture2D) -> Image:
	var image := texture.get_image().duplicate() as Image
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGB8)
	return image

func check_material() -> void:
	var source: Dictionary = Steel.read_images()
	verify(source.status == "ready", "All three declared material images decode at their specified extents.")
	if source.status != "ready":
		return
	var material: StandardMaterial3D = Steel.material()
	verify(material != null and material == Steel.material() and Steel.source_status == "ready",
		"The complete set creates one shared material and records its actual profile.")
	if material == null:
		return
	verify(material.ao_texture == material.roughness_texture and material.ao_texture == material.metallic_texture,
		"Packed scalar data is shared instead of allocating three independent image copies.")
	var loaded_albedo := base_image(material.albedo_texture)
	var loaded_normal := base_image(material.normal_texture)
	var loaded_arm := base_image(material.roughness_texture)
	for role in source.images:
		(source.images[role] as Image).convert(Image.FORMAT_RGB8)
	verify(loaded_albedo.get_data() == source.images.albedo.get_data(), "The sampled albedo keeps the prepared sRGB bytes without a second color transform.")
	verify(loaded_normal.get_data() == source.images.normal.get_data(), "The OpenGL normal data is neither flipped nor reinterpreted on load.")
	verify(loaded_arm.get_data() == source.images.arm.get_data(), "Linear packed data is not accidentally gamma-transformed.")
	var scalar_matches := true
	var distinguishable := false
	var valid_normals := true
	for y in range(8, 512, 32):
		for x in range(8, 512, 32):
			var packed: Color = loaded_arm.get_pixel(x, y)
			var expected: Color = source.images.arm.get_pixel(x, y)
			scalar_matches = scalar_matches and channel(packed, material.roughness_texture_channel) == expected.g
			scalar_matches = scalar_matches and channel(packed, material.metallic_texture_channel) == expected.b
			scalar_matches = scalar_matches and channel(packed, material.ao_texture_channel) == expected.r
			distinguishable = distinguishable or absf(expected.g - expected.b) > 0.05
			var encoded := loaded_normal.get_pixel(x * 2, y * 2)
			var normal := Vector3(encoded.r, encoded.g, encoded.b) * 2.0 - Vector3.ONE
			valid_normals = valid_normals and normal.is_finite() and normal.z > 0 and absf(normal.length() - 1) < 0.02
	verify(scalar_matches and distinguishable, "The actual source distinguishes green roughness, blue metal and red occlusion wiring.")
	verify(valid_normals, "Decoded tangent normals remain finite unit directions in the OpenGL positive-Z hemisphere.")
	for texture in [material.albedo_texture, material.normal_texture, material.roughness_texture]:
		var image: Image = texture.get_image()
		verify(image.has_mipmaps() and image.get_mipmap_count() == (9 if image.get_width() == 512 else 10),
			"Each loaded map includes the complete downsample chain for normal play distance.")
	verify(material.uv1_triplanar and material.uv1_world_triplanar and material.uv1_scale == Vector3(0.5, 0.5, 0.5),
		"The declared two-metre source uses continuous static world mapping.")
	verify(material.normal_enabled and material.ao_enabled and material.ao_light_affect == 0.0,
		"Surface normal and ambient-only occlusion inputs leave direct lighting independent.")

func check_invalid_sets() -> void:
	verify(controls_dir.is_absolute_path() and not DirAccess.dir_exists_absolute(controls_dir),
		"Negative controls use a fresh owned external directory.")
	if not controls_dir.is_absolute_path() or DirAccess.dir_exists_absolute(controls_dir):
		return
	DirAccess.make_dir_recursive_absolute(controls_dir)
	verify(Steel.read_images(controls_dir).status == "missing", "A historical payload with no bitmap set is distinguished from a complete set.")
	var small := Image.create(1, 1, false, Image.FORMAT_RGB8)
	small.fill(Color.WHITE)
	verify(small.save_webp(controls_dir.path_join(Steel.FILES.albedo), false) == OK, "Retain a valid image with deliberately wrong dimensions.")
	verify(Steel.read_images(controls_dir).get("reason") == "incomplete_material_set", "A partial set is rejected before attempting mixed material loading.")
	for role in ["normal", "arm"]:
		verify(DirAccess.copy_absolute(Steel.ROOT.path_join(Steel.FILES[role]), controls_dir.path_join(Steel.FILES[role])) == OK,
			"Retain unchanged companion images for the dimension control.")
	verify(Steel.read_images(controls_dir).get("reason") == "invalid_albedo", "A fully named but wrong-sized set cannot be labeled ready.")
	verify(Steel.source_status == "ready", "Negative-path inspection cannot poison the live material cache.")

func check_foundation(legacy: bool) -> void:
	var view := VisualWorld.new()
	view.legacy_fixture = legacy
	root.add_child(view)
	view._build_world()
	var panels := 0
	var seen: Dictionary = {}
	var geometry_unchanged := true
	var material_correct := true
	for node in view.get_children():
		if not node is MeshInstance3D or node.get_meta("surface_role", "") != "foundation":
			continue
		panels += 1
		var x := roundi(node.position.x / 1.65)
		var z := roundi(node.position.z / 1.65)
		seen[Vector2i(x, z)] = true
		geometry_unchanged = geometry_unchanged and x >= -2 and x <= 4 and z >= -2 and z <= 4
		geometry_unchanged = geometry_unchanged and node.position.is_equal_approx(Vector3(x * 1.65, -0.08, z * 1.65))
		geometry_unchanged = geometry_unchanged and node.mesh.get_aabb().size.is_equal_approx(Vector3(1.615, 0.12, 1.615))
		material_correct = material_correct and (node.material_override != Steel.material() if legacy else node.material_override == Steel.material())
	verify(panels == 49 and seen.size() == 49 and geometry_unchanged, "The actual world builder retains all literal panel cells, dimensions and elevations.")
	verify(material_correct and view.get_meta("foundation_surface") == ("legacy" if legacy else "ready"),
		"Only the physical presentation chooses the scanned material; the legacy fixture remains procedural.")
	verify(view.model == null and view.actor_world == null and view.state.is_empty() and view.request_sequence == 0,
		"Foundation assembly creates no Model, native actor, request or projected state.")
	view.free()

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--controls-dir="):
			controls_dir = argument.trim_prefix("--controls-dir=")
		elif argument == "--material-only":
			material_only = true
	call_deferred("_check")

func _check() -> void:
	check_material()
	check_invalid_sets()
	if not material_only:
		check_foundation(false)
		check_foundation(true)
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
		"scope": "image/material and literal foundation assembly", "native_gameplay": "not_run",
		"rendered_quality": "not_assessed", "desktop": "not_used"}))
	quit(1 if failed else 0)
