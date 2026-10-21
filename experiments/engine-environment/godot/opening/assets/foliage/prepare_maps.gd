extends SceneTree
## Offline asset preparation. No game, authority, scene or desktop starts.
func fail(message: String) -> void:
	push_error(message)
	quit(1)

func nearest_byte(value: float) -> int:
	return clampi(roundi(value * 255.0), 0, 255)

func prepare_stone(family: String) -> void:
	var output := family.path_join("prepared-stone")
	if DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_absolute(output) != OK:
		fail("Use a fresh stone preparation directory; preserve earlier results.")
		return
	var files := {"albedo": "source_albedo.jpg", "normal": "source_normal.png", "arm": "source_arm.png"}
	var images := {}
	for role in files:
		var image := Image.load_from_file(family.path_join(files[role]))
		if image == null or image.is_empty() or image.get_size() != Vector2i(1024, 1024):
			fail("Unexpected stone source decode or dimensions: " + role)
			return
		image.convert(Image.FORMAT_RGB8 if role == "albedo" else Image.FORMAT_RGBF)
		images[role] = image
	images.normal.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	images.arm.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	var records := {}
	var passed := true
	var total := 0
	for role in ["albedo", "normal", "arm"]:
		var image: Image = images[role]
		var maximum_normal_error := 0.0
		if role != "albedo":
			var bytes := PackedByteArray()
			bytes.resize(image.get_width() * image.get_height() * 3)
			for y in range(image.get_height()):
				for x in range(image.get_width()):
					var color := image.get_pixel(x, y)
					if role == "normal":
						var normal := Vector3(color.r * 2 - 1, color.g * 2 - 1, color.b * 2 - 1)
						if not normal.is_finite() or normal.length_squared() < 0.000001:
							fail("Invalid resized stone normal.")
							return
						normal = normal.normalized()
						color = Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5)
					var at := (y * image.get_width() + x) * 3
					bytes[at] = nearest_byte(color.r)
					bytes[at + 1] = nearest_byte(color.g)
					bytes[at + 2] = nearest_byte(color.b)
					if role == "normal":
						var vector := Vector3(bytes[at], bytes[at + 1], bytes[at + 2]) / 255.0 * 2 - Vector3.ONE
						maximum_normal_error = maxf(maximum_normal_error, absf(vector.length() - 1.0))
			image = Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGB8, bytes)
		var name_value: String = "stone_normal_gl.webp" if role == "normal" else "stone_" + role + ".webp"
		var destination := output.path_join(name_value)
		if image.save_webp(destination, role == "albedo", 0.80 if role == "albedo" else 1.0) != OK:
			fail("Cannot publish prepared stone map: " + role)
			return
		var decoded := Image.load_from_file(destination)
		if decoded == null or decoded.is_empty() or decoded.get_size() != image.get_size():
			fail("Prepared stone map failed to decode: " + role)
			return
		decoded.convert(Image.FORMAT_RGB8)
		var exact := decoded.get_data() == image.get_data()
		var size := FileAccess.get_file_as_bytes(destination).size()
		total += size
		var record := {"file": name_value, "width": image.get_width(), "height": image.get_height(), "bytes": size,
			"sha256": FileAccess.get_sha256(destination), "decoded_rgb8_exact": exact}
		if role == "albedo":
			var sum_error := 0.0
			for y in range(1024):
				for x in range(1024):
					var a := image.get_pixel(x, y)
					var b := decoded.get_pixel(x, y)
					sum_error += pow(a.r - b.r, 2) + pow(a.g - b.g, 2) + pow(a.b - b.b, 2)
			var rmse := sqrt(sum_error / (1024.0 * 1024.0 * 3.0))
			record.albedo_rmse_srgb = rmse
			passed = passed and rmse < 0.025
		else:
			passed = passed and exact and maximum_normal_error < 0.01
			if role == "normal":
				record.maximum_unit_length_error = maximum_normal_error
		records[role] = record
	passed = passed and total <= 1000000
	var result := {"status": "pass" if passed else "fail", "maps": records, "total_bytes": total,
		"processing": "Original 1024px sRGB color uses WebP quality 0.80. Linear ARM is Lanczos resized to 256 and explicitly nearest-rounded RGB8. OpenGL normal is resized to 512, vector-normalized and nearest-rounded RGB8. Data maps use lossless WebP, no gamma transform or green flip.",
		"limits": "Source-map preparation only; numerical bounds do not establish rendered quality, physical detail or human preference."}
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	if file == null:
		fail("Cannot retain the stone preparation result.")
		return
	file.store_string(JSON.stringify(result, "  ") + "\n")
	file.close()
	print(JSON.stringify(result))
	quit(0 if passed else 1)

func _initialize() -> void:
	var family := ""
	var material := "foliage"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--family="):
			family = argument.trim_prefix("--family=")
		elif argument.begins_with("--material="):
			material = argument.trim_prefix("--material=")
	if not family.is_absolute_path():
		fail("Use an absolute owned source family.")
		return
	if material == "stone":
		prepare_stone(family)
		return
	if material != "foliage":
		fail("Choose the declared foliage or stone preparation.")
		return
	var output := family.path_join("prepared-maps")
	if DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_absolute(output) != OK:
		fail("Use a fresh output directory; preserve earlier results.")
		return
	var files := {"albedo": "source_albedo.jpg", "alpha": "source_alpha.png", "normal": "source_normal.png", "arm": "source_arm.png"}
	var images := {}
	for role in files:
		var image := Image.load_from_file(family.path_join(files[role]))
		if image == null or image.is_empty() or image.get_size() != Vector2i(1024, 1024):
			fail("Unexpected source image dimensions or decode: " + role)
			return
		image.convert(Image.FORMAT_RGBF)
		images[role] = image
	var source_coverage := 0
	for y in range(1024):
		for x in range(1024):
			if images.alpha.get_pixel(x, y).r >= 0.5:
				source_coverage += 1
	images.albedo.resize(384, 384, Image.INTERPOLATE_LANCZOS)
	images.alpha.resize(384, 384, Image.INTERPOLATE_LANCZOS)
	images.normal.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	images.arm.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	var records := {}
	var passed := true
	for role in ["albedo", "normal", "arm"]:
		var extent := 384 if role == "albedo" else 256
		var channels := 4 if role == "albedo" else 3
		var bytes := PackedByteArray()
		bytes.resize(extent * extent * channels)
		var coverage := 0
		var maximum_normal_error := 0.0
		for y in range(extent):
			for x in range(extent):
				var color: Color = images[role].get_pixel(x, y)
				if role == "normal":
					var normal := Vector3(color.r * 2 - 1, color.g * 2 - 1, color.b * 2 - 1)
					if not normal.is_finite() or normal.length_squared() < 0.000001:
						fail("Invalid source normal after resize.")
						return
					normal = normal.normalized()
					color = Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5)
				var at := (y * extent + x) * channels
				bytes[at] = nearest_byte(color.r)
				bytes[at + 1] = nearest_byte(color.g)
				bytes[at + 2] = nearest_byte(color.b)
				if role == "albedo":
					bytes[at + 3] = nearest_byte(images.alpha.get_pixel(x, y).r)
					if bytes[at + 3] >= 128:
						coverage += 1
				elif role == "normal":
					var decoded := Vector3(bytes[at], bytes[at + 1], bytes[at + 2]) / 255.0 * 2.0 - Vector3.ONE
					maximum_normal_error = maxf(maximum_normal_error, absf(decoded.length() - 1.0))
		var packed := Image.create_from_data(extent, extent, false, Image.FORMAT_RGBA8 if role == "albedo" else Image.FORMAT_RGB8, bytes)
		var destination := output.path_join(role + ".png")
		if packed.save_png(destination) != OK:
			fail("Cannot publish prepared texture: " + role)
			return
		var decoded := Image.load_from_file(destination)
		var exact := decoded != null and decoded.get_size() == packed.get_size() and decoded.get_data() == bytes
		passed = passed and exact and maximum_normal_error < 0.01
		var record := {"extent": extent, "bytes": FileAccess.get_file_as_bytes(destination).size(), "sha256": FileAccess.get_sha256(destination), "decoded_bytes_exact": exact}
		if role == "albedo":
			var original := float(source_coverage) / (1024 * 1024)
			var resized := float(coverage) / (384 * 384)
			record.source_cutout_coverage = original
			record.prepared_cutout_coverage = resized
			passed = passed and original > 0.02 and original < 0.98 and absf(original - resized) < 0.025
		elif role == "normal":
			record.maximum_unit_length_error = maximum_normal_error
		records[role] = record
	var result := {"status": "pass" if passed else "fail", "maps": records,
		"processing": "Lanczos resize; photographed sRGB color plus separate linear opacity; normalized OpenGL normal with nearest RGB8 encoding; packed linear ARM unchanged in channel meaning. Lossless PNG delivery, no normal green flip.",
		"limits": "Asset preparation and decode evidence only; no rendered quality or game authority."}
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	if file == null:
		fail("Cannot retain preparation result.")
		return
	file.store_string(JSON.stringify(result, "  ") + "\n")
	file.close()
	print(JSON.stringify(result))
	quit(0 if passed else 1)
