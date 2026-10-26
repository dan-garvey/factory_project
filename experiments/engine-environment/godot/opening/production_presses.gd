extends RefCounted
## Render resources only; no scene controller or simulation authority.
const Geometry = preload("res://opening/site_geometry.gd")
const ProductionCoating = preload("res://opening/production_surfaces.gd").ProductionCoating
const ProductionMeshAssembly = preload("res://opening/production_surfaces.gd").ProductionMeshAssembly
const ProductionSteelFloor = preload("res://opening/production_surfaces.gd").ProductionSteelFloor
const ProductionTransmissionFinish = preload("res://opening/production_surfaces.gd").ProductionTransmissionFinish
const ProductionVisuals = preload("res://opening/production_surfaces.gd").ProductionVisuals

class ProductionPressArt:
	extends RefCounted
	## Authored support components for the existing confirmed processor.
	const ROOT := "res://opening/assets/press-support"
	const IMAGES := {"albedo": "cast_albedo.jpg", "normal": "cast_normal.webp", "arm": "cast_arm.webp"}
	static var mesh: ArrayMesh
	static var finish: StandardMaterial3D
	static var source_status := "uninitialized"

	static func resource_status(directory: String = ROOT) -> String:
		var files: Array = ["press_support.gltf", "press_support.bin"]
		files.append_array(IMAGES.values())
		var present := 0
		for name_value: String in files:
			if FileAccess.file_exists(directory.path_join(name_value)):
				present += 1
		if present == 0:
			return "missing"
		return "complete" if present == files.size() else "incomplete"

	static func _prepare() -> void:
		source_status = resource_status()
		if source_status == "missing":
			return
		if source_status != "complete":
			push_error("The sourced press support resource set is incomplete.")
			return
		source_status = "invalid"
		var images := ProductionSteelFloor.read_images(ROOT, IMAGES, Vector2i(512, 512))
		if images.status != "ready":
			push_error("Cannot decode the sourced press support material.")
			return
		var document := GLTFDocument.new()
		var imported := GLTFState.new()
		if document.append_from_file(ROOT.path_join("press_support.gltf"), imported) != OK:
			push_error("Cannot load the prepared press support component.")
			return
		var sources := imported.get_meshes()
		if sources.size() != 1 or sources[0].mesh == null or sources[0].mesh.get_surface_count() != 1:
			push_error("The press support must contain one prepared visual mesh.")
			return
		var prepared: ArrayMesh = sources[0].mesh.get_mesh()
		var arrays := prepared.surface_get_arrays(0)
		if arrays[Mesh.ARRAY_TANGENT] == null or arrays[Mesh.ARRAY_TANGENT].is_empty():
			var surface := SurfaceTool.new()
			surface.create_from(prepared, 0)
			surface.generate_tangents()
			prepared = surface.commit()
		for role: String in images.images:
			var image: Image = images.images[role]
			if image.generate_mipmaps(role == "normal") != OK:
				push_error("Cannot generate press support mipmaps.")
				return
		var material := StandardMaterial3D.new()
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_color = Color.WHITE
		material.albedo_texture = ImageTexture.create_from_image(images.images.albedo)
		var arm := ImageTexture.create_from_image(images.images.arm)
		material.metallic = 1.0
		material.metallic_texture = arm
		material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		material.roughness = 1.0
		material.roughness_texture = arm
		material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		material.ao_enabled = true
		material.ao_texture = arm
		material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		material.ao_light_affect = 0.0
		material.normal_enabled = true
		material.normal_texture = ImageTexture.create_from_image(images.images.normal)
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		mesh = prepared
		finish = material
		source_status = "ready"

	static func mount(parent: Node3D) -> bool:
		if source_status == "uninitialized":
			_prepare()
		if source_status != "ready":
			return false
		for side in [-1.0, 1.0]:
			var support := MeshInstance3D.new()
			support.name = "CastPressSupportLeft" if side < 0 else "CastPressSupportRight"
			support.mesh = mesh
			support.material_override = finish
			support.position = Vector3(side * 0.48, 0.24, -0.38)
			if side > 0:
				support.rotation.y = PI
			support.set_meta("detail_role", "CastPressSupport")
			support.set_meta("source_asset", "Poly Haven drill_press_01")
			parent.add_child(support)
		return true

class ProductionPressCrownArt:
	extends RefCounted
	## Fixed original castings around the unchanged tool and guide shafts.
	static func _part(parent: Node3D, role: String, mesh: Mesh, at: Vector3,
			finish: StandardMaterial3D) -> void:
		var part := MeshInstance3D.new()
		part.name = role
		part.set_meta("press_crown_role", role)
		part.mesh = mesh
		part.position = at
		part.material_override = finish
		parent.add_child(part)

	static func mount(parent: Node3D, color: Color) -> bool:
		var cast_finish := ProductionTransmissionFinish.material("cast", Color("56635f"), 0.55, 0.74)
		var steel := ProductionTransmissionFinish.material("worked", Color("a6b4af"), 0.85, 0.38)
		var guide_finish := ProductionTransmissionFinish.material("worked", Color("b87945"), 0.85, 0.4)
		if cast_finish == null or steel == null or guide_finish == null:
			return false
		var crown := Node3D.new()
		crown.name = "PressCrown"
		parent.add_child(crown)
		var shoulder := PackedVector2Array([Vector2(-0.64, -0.14), Vector2(-0.55, -0.14),
			Vector2(-0.40, -0.08), Vector2(-0.25, -0.08), Vector2(-0.25, 0.12),
			Vector2(-0.64, 0.12)])
		for right in [false, true]:
			var profile := shoulder.duplicate()
			if right:
				for n in range(profile.size()):
					profile[n].x = -profile[n].x
			_part(crown, "CastShoulderRight" if right else "CastShoulderLeft",
				ProductionVisuals.prism_mesh(profile, 0.36, 0.007), Vector3(0, 1.5, -0.3), cast_finish)
		# The rear tie joins the shoulders without filling the ram's bore.
		_part(crown, "RearTie", ProductionVisuals.box_mesh(Vector3(0.54, 0.18, 0.265)),
			Vector3(0, 1.53, -0.3475), cast_finish)
		var housing := PackedVector2Array([Vector2(0.083, -0.135), Vector2(0.115, -0.135),
			Vector2(0.14, -0.115), Vector2(0.14, 0.11), Vector2(0.12, 0.135),
			Vector2(0.083, 0.135), Vector2(0.083, -0.135)])
		_part(crown, "RamHousing", ProductionVisuals.turned_mesh(housing), Vector3(0, 1.465, -0.08), cast_finish)
		var liner := PackedVector2Array([Vector2(0.079, -0.125), Vector2(0.083, -0.125),
			Vector2(0.083, 0.125), Vector2(0.079, 0.125), Vector2(0.079, -0.125)])
		_part(crown, "RamLiner", ProductionVisuals.turned_mesh(liner), Vector3(0, 1.465, -0.08), steel)
		var socket := PackedVector2Array([Vector2(0.043, -0.04), Vector2(0.058, -0.04),
			Vector2(0.068, -0.03), Vector2(0.068, 0.03), Vector2(0.058, 0.04),
			Vector2(0.043, 0.04), Vector2(0.043, -0.04)])
		for side in [-1.0, 1.0]:
			_part(crown, "GuideSocketLeft" if side < 0 else "GuideSocketRight",
				ProductionVisuals.turned_mesh(socket), Vector3(side * 0.34, 1.39, -0.19), guide_finish)
		return true

class ProductionPressRearFrameArt:
	extends RefCounted
	## A fixed, original H-frame behind the existing sourced columns. It carries
	## no separate support, collision, material or press-work authority.
	static var meshes: Dictionary = {}

	static func _part(parent: Node3D, role: String, mesh: Mesh, at: Vector3,
			finish: StandardMaterial3D) -> MeshInstance3D:
		var part := MeshInstance3D.new()
		part.name = role
		part.set_meta("press_frame_role", role)
		part.mesh = mesh
		part.position = at
		part.material_override = finish
		parent.add_child(part)
		return part

	static func mount(parent: Node3D, color: Color) -> bool:
		var cast_finish := ProductionTransmissionFinish.material("cast", Color("56635f"), 0.55, 0.74)
		if cast_finish == null:
			return false
		if not meshes.has("tie"):
			# The lower tie remains behind the feed bed and joins both sourced
			# columns, unlike an unsupported decorative bar across the tool.
			meshes.tie = ProductionVisuals.box_mesh(Vector3(0.93, 0.14, 0.13))
			meshes.foot = ProductionVisuals.box_mesh(Vector3(0.27, 0.06, 0.22))
			for side in [-1.0, 1.0]:
				var profile := PackedVector2Array([
					Vector2(0.35, 0.29), Vector2(0.62, 0.29),
					Vector2(0.59, 0.30), Vector2(0.53, 0.52),
					Vector2(0.44, 0.52), Vector2(0.42, 0.36)])
				var upright := PackedVector2Array([
					Vector2(0.53, 0.24), Vector2(0.64, 0.24),
					Vector2(0.61, 0.36),
					Vector2(0.65, 1.34), Vector2(0.65, 1.42),
					Vector2(0.47, 1.42), Vector2(0.47, 1.34),
					Vector2(0.51, 0.36)])
				for n in range(profile.size()):
					profile[n].x *= side
				for n in range(upright.size()):
					upright[n].x *= side
				meshes["gusset_n" if side < 0 else "gusset_p"] = ProductionVisuals.prism_mesh(profile, 0.14, 0.004)
				meshes["upright_n" if side < 0 else "upright_p"] = ProductionVisuals.prism_mesh(upright, 0.12, 0.004)
		var frame := Node3D.new()
		frame.name = "PressRearFrame"
		parent.add_child(frame)
		_part(frame, "RearLowerTie", meshes.tie, Vector3(0, 0.30, -0.46), cast_finish)
		for side in [-1.0, 1.0]:
			_part(frame, "RearFootLeft" if side < 0 else "RearFootRight", meshes.foot,
				Vector3(side * 0.48, 0.27, -0.40), cast_finish)
			_part(frame, "RearGussetLeft" if side < 0 else "RearGussetRight",
				meshes["gusset_n" if side < 0 else "gusset_p"], Vector3(0, 0, -0.46), cast_finish)
			_part(frame, "FrontUprightLeft" if side < 0 else "FrontUprightRight",
				meshes["upright_n" if side < 0 else "upright_p"], Vector3(0, 0, -0.25), cast_finish)
		return true

class ProductionPressDieArt:
	extends RefCounted
	## Passive rigid tooling. Working planes and the existing motion anchor stay literal.
	static var meshes: Dictionary = {}

	static func tool_mesh(kind: String = "press") -> ArrayMesh:
		if kind != "press":
			return null
		var key := "tool_" + kind
		if meshes.has(key):
			return meshes[key]
		var mesh := ArrayMesh.new()
		var holder := PackedVector2Array([
			Vector2(-0.28, -0.025), Vector2(-0.27, -0.045), Vector2(-0.25, -0.045),
			Vector2(-0.25, -0.035), Vector2(0.25, -0.035), Vector2(0.25, -0.045),
			Vector2(0.27, -0.045), Vector2(0.28, -0.025), Vector2(0.28, 0.060),
			Vector2(0.255, 0.085), Vector2(-0.255, 0.085), Vector2(-0.28, 0.060)])
		ProductionMeshAssembly.append_surface(mesh, "ToolHolder", [[ProductionVisuals.prism_mesh(holder, 0.48, 0.004), Transform3D.IDENTITY]])
		ProductionMeshAssembly.append_surface(mesh, "WorkingFace", [[ProductionVisuals.box_mesh(Vector3(0.50, 0.05, 0.55)),
			Transform3D(Basis.IDENTITY, Vector3(0, -0.06, 0))]])
		var poses: Array[Transform3D] = []
		for side in [-1.0, 1.0]:
			for x in [-0.205, 0.205]:
				poses.append(Transform3D(Basis(Quaternion(Vector3.UP, Vector3.BACK * side)), Vector3(x, 0.025, side * 0.24)))
		var locks: Array = []
		for side in [-1.0, 1.0]:
			locks.append([ProductionVisuals.box_mesh(Vector3(0.02, 0.06, 0.38)),
				Transform3D(Basis.IDENTITY, Vector3(side * 0.27, 0.025, 0))])
			locks.append([ProductionVisuals.box_mesh(Vector3(0.36, 0.045, 0.025)),
				Transform3D(Basis.IDENTITY, Vector3(0, 0.035, side * 0.255))])
		ProductionMeshAssembly.append_hardware(mesh, poses, locks)
		meshes[key] = mesh
		return mesh

	static func anvil_mesh() -> ArrayMesh:
		if meshes.has("anvil"):
			return meshes.anvil
		var mesh := ArrayMesh.new()
		var saddle := PackedVector2Array([
			Vector2(-0.35, -0.08), Vector2(0.21, -0.08), Vector2(0.21, -0.02),
			Vector2(0.35, -0.02), Vector2(0.35, 0.005), Vector2(0.27, 0.005), Vector2(0.24, 0.04),
			Vector2(-0.24, 0.04), Vector2(-0.24, -0.015), Vector2(-0.27, -0.045), Vector2(-0.35, -0.045)])
		ProductionMeshAssembly.append_surface(mesh, "AnvilSaddle", [[ProductionVisuals.prism_mesh(saddle, 0.63, 0.004), Transform3D.IDENTITY]])
		ProductionMeshAssembly.append_surface(mesh, "WorkingFace", [[ProductionVisuals.box_mesh(Vector3(0.52, 0.04, 0.51)),
			Transform3D(Basis.IDENTITY, Vector3(0, 0.06, 0))]])
		var poses: Array[Transform3D] = []
		for x in [-0.305, 0.305]:
			for z in [-0.255, 0.255]:
				# The outlet-side foot is relieved above the existing output plate.
				poses.append(Transform3D(Basis.IDENTITY, Vector3(x, 0.005 if x > 0 else -0.045, z)))
		ProductionMeshAssembly.append_hardware(mesh, poses)
		meshes.anvil = mesh
		return mesh

	static func pedestal_mesh() -> ArrayMesh:
		if not meshes.has("pedestal"):
			var rib := PackedVector2Array([
				Vector2(-0.05, -0.07), Vector2(0.05, -0.07), Vector2(0.05, -0.045),
				Vector2(0.025, -0.045), Vector2(0.022, 0.045), Vector2(0.045, 0.045),
				Vector2(0.045, 0.07), Vector2(-0.045, 0.07), Vector2(-0.045, 0.045),
				Vector2(-0.022, 0.045), Vector2(-0.025, -0.045), Vector2(-0.05, -0.045)])
			meshes.pedestal = ProductionVisuals.prism_mesh(rib, 0.53, 0.002)
		return meshes.pedestal

	static func mount(parent: Node3D, anvil: MeshInstance3D, head: MeshInstance3D) -> void:
		var holder := ProductionCoating.material(Color("58634c"))
		var saddle := ProductionCoating.material(Color("394a44"))
		var face := ProductionTransmissionFinish.material("worked", Color("a6b4af"), 0.85, 0.32)
		var hardware := ProductionTransmissionFinish.material("worked", Color("b8c3bb"), 0.85, 0.38)
		if holder == null or saddle == null or face == null or hardware == null:
			return
		for pair in [[head, tool_mesh(), holder], [anvil, anvil_mesh(), saddle]]:
			var part: MeshInstance3D = pair[0]
			part.mesh = pair[1]
			part.material_override = null
			part.set_surface_override_material(0, pair[2])
			part.set_surface_override_material(1, face)
			part.set_surface_override_material(2, hardware)
			part.set_meta("press_die_role", str(part.name))
		for side in [-1.0, 1.0]:
			var rib := MeshInstance3D.new()
			rib.name = "AnvilPedestalLeft" if side < 0 else "AnvilPedestalRight"
			# Keep the outlet side open without entering the vertical drive journal.
			rib.position = Vector3(side * 0.16, 0.31, 0.05)
			rib.mesh = pedestal_mesh()
			rib.material_override = saddle
			rib.set_meta("press_die_role", "AnvilPedestal")
			parent.add_child(rib)

class ProductionPressTrayArt:
	extends RefCounted
	## Fixed sheet and brackets. The receiving datum and output item never move.
	static var meshes: Dictionary = {}

	static func tray_mesh() -> ArrayMesh:
		if not meshes.has("tray"):
			# An eight-millimetre floor with folded sides and short returned lips.
			# The open ends leave the existing output accessible; all folds stay
			# outside the full declared plate footprint, not just its centre.
			var section := PackedVector2Array([
				Vector2(-0.24, 0.017), Vector2(0.24, 0.017), Vector2(0.24, 0.040),
				Vector2(0.228, 0.040), Vector2(0.228, 0.032), Vector2(0.232, 0.032),
				Vector2(0.232, 0.025), Vector2(-0.232, 0.025), Vector2(-0.232, 0.032),
				Vector2(-0.228, 0.032), Vector2(-0.228, 0.040), Vector2(-0.24, 0.040)])
			meshes.tray = ProductionVisuals.prism_mesh(section, 0.58, 0.0006)
		return meshes.tray

	static func bracket_mesh() -> ArrayMesh:
		if meshes.has("bracket"):
			return meshes.bracket
		var section := PackedVector2Array([
			Vector2(-0.030, -0.0535), Vector2(0.030, -0.0535), Vector2(0.030, -0.0435),
			Vector2(0.012, -0.0435), Vector2(0.012, 0.0375), Vector2(0.028, 0.0375),
			Vector2(0.028, 0.0535), Vector2(-0.028, 0.0535), Vector2(-0.028, 0.0375),
			Vector2(-0.012, 0.0375), Vector2(-0.012, -0.0435), Vector2(-0.030, -0.0435)])
		var mesh := ArrayMesh.new()
		ProductionMeshAssembly.append_surface(mesh, "Bracket", [[ProductionVisuals.prism_mesh(section, 0.32, 0.0008), Transform3D.IDENTITY]])
		var fasteners: Array = []
		for x in [-0.021, 0.021]:
			for z in [-0.12, 0.12]:
				fasteners.append([ProductionVisuals.fastener_head_mesh(),
					Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.18), Vector3(x, -0.04134, z))])
		ProductionMeshAssembly.append_surface(mesh, "FootFasteners", fasteners)
		meshes.bracket = mesh
		return mesh

	static func mount(parent: Node3D, tray: MeshInstance3D) -> void:
		var sheet := ProductionTransmissionFinish.material("worked", Color("a6b4af"), 0.85, 0.5)
		var bracket_finish := ProductionCoating.material(Color("394a44"))
		var hardware := ProductionTransmissionFinish.material("worked", Color("b8c3bb"), 0.85, 0.38)
		if sheet == null or bracket_finish == null or hardware == null:
			return
		tray.mesh = tray_mesh()
		tray.material_override = sheet
		tray.set_meta("press_tray_role", "FormedPan")
		for index in range(2):
			var bracket := MeshInstance3D.new()
			bracket.name = "TrayBracketLeft" if index == 0 else "TrayBracketRight"
			bracket.position = Vector3(0.40 if index == 0 else 0.62, 0.2935, 0.15)
			bracket.mesh = bracket_mesh()
			bracket.set_surface_override_material(0, bracket_finish)
			bracket.set_surface_override_material(1, hardware)
			bracket.set_meta("press_tray_role", "FixedBracket")
			parent.add_child(bracket)

class ProductionDriveJournalArt:
	extends RefCounted
	## Turned presentation inside the original native journal cylinder.
	static var horizontal_press_mesh: ArrayMesh
	static var z_input_post_mesh: ArrayMesh
	static var collector_bearing_mesh: ArrayMesh
	static func mesh(height: float, radius: float = 0.085) -> ArrayMesh:
		var half := height / 2.0
		# Keep the full central bearing span. End relief and center marks are
		# visual machining details, without a new coupling or contact rule.
		var profile := PackedVector2Array([
			Vector2(0, -half + 0.020), Vector2(0.014, -half + 0.020),
			Vector2(0.028, -half), Vector2(0.071, -half),
			Vector2(0.085, -half + 0.014), Vector2(0.085, -half + 0.040),
			Vector2(0.081, -half + 0.044), Vector2(0.081, -half + 0.058),
			Vector2(0.085, -half + 0.062), Vector2(0.085, half - 0.062),
			Vector2(0.081, half - 0.058), Vector2(0.081, half - 0.044),
			Vector2(0.085, half - 0.040), Vector2(0.085, half - 0.014),
			Vector2(0.071, half), Vector2(0.028, half),
			Vector2(0.014, half - 0.020), Vector2(0, half - 0.020)])
		if radius != 0.085:
			var ratio := radius / 0.085
			for n in range(profile.size()):
				profile[n] = Vector2(profile[n].x * ratio, profile[n].y)
		return ProductionVisuals.turned_mesh(profile)

	static func material() -> StandardMaterial3D:
		return ProductionTransmissionFinish.material("worked", Color("a6b4af"), 0.85, 0.38)

	static func press_mesh() -> ArrayMesh:
		if horizontal_press_mesh == null:
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			# The inboard shoulder clears the original stamped-plate hardware;
			# the outer cuff keeps the established attachment radius and plane.
			var end_mesh := ProductionVisuals.turned_mesh(PackedVector2Array([
				Vector2(0, -0.070), Vector2(0.014, -0.070), Vector2(0.028, -0.090),
				Vector2(0.065, -0.090), Vector2(0.077, -0.078), Vector2(0.077, 0.050),
				Vector2(0.078, 0.055), Vector2(0.085, 0.060), Vector2(0.085, 0.076),
				Vector2(0.071, 0.090), Vector2(0.028, 0.090), Vector2(0.014, 0.070),
				Vector2(0, 0.070)]))
			# Preserve the two original external ends. The working body between
			# them is not an exposed through-shaft across the anvil.
			for side in [-1.0, 1.0]:
				var basis := Basis(Vector3.RIGHT, PI) if side < 0 else Basis.IDENTITY
				surface.append_from(end_mesh, 0, Transform3D(basis, Vector3(0, side * 0.585, 0)))
			horizontal_press_mesh = surface.commit()
		return horizontal_press_mesh

	static func _press_fixed(parent: Node3D, name_value: String, role: String,
			mesh_value: ArrayMesh, at: Vector3, basis_value: Basis = Basis.IDENTITY) -> void:
		var part := MeshInstance3D.new()
		part.name = name_value
		part.position = at
		part.basis = basis_value
		part.mesh = mesh_value
		part.material_override = ProductionTransmissionFinish.material("worked", Color("878d7f"), 0.85, 0.42) \
			if role == "Bearing" else ProductionCoating.material(Color("58634c"))
		part.set_meta("press_input_role", role)
		parent.add_child(part)

	static func mount_press_bearings(parent: Node3D, axis: Vector3) -> void:
		var ring := ProductionVisuals.turned_mesh(PackedVector2Array([
			Vector2(0.087, -0.010), Vector2(0.089, -0.015), Vector2(0.096, -0.015),
			Vector2(0.100, -0.011), Vector2(0.100, 0.011), Vector2(0.096, 0.015),
			Vector2(0.089, 0.015), Vector2(0.087, 0.010), Vector2(0.087, -0.010)]))
		for side in [-1.0, 1.0]:
			var suffix := "Left" if side < 0 else "Right"
			var at: Vector3 = axis * float(side) * 0.66
			_press_fixed(parent, "PressInputBearing" + suffix, "Bearing", ring,
				at + Vector3.UP * Geometry.ANCHOR_HEIGHT, Basis(Quaternion(Vector3.UP, axis)))
			if axis == Vector3.RIGHT:
				# The raised shared axle needs a taller rear load path. Keep the
				# narrow upper ear outside the original journal radius.
				var deck_top := 0.24
				var post_top := Geometry.ANCHOR_HEIGHT - 0.105
				_press_fixed(parent, "PressInputPost" + suffix, "Post",
					ProductionVisuals.box_mesh(Vector3(0.10, post_top - deck_top, 0.12)),
					at + Vector3(0, (post_top + deck_top) * 0.5, -0.23))
				_press_fixed(parent, "PressInputBracket" + suffix, "Bracket",
					ProductionVisuals.box_mesh(Vector3(0.06, 0.13, 0.16)),
					at + Vector3(0, Geometry.ANCHOR_HEIGHT - 0.08, -0.17))
			else:
				if z_input_post_mesh == null:
					# An offset cast cheek reaches the annular housing but leaves
					# the central shaft and its original clearance unobstructed.
					var cheek := PackedVector2Array([Vector2(0.09, 0.24),
						Vector2(0.24, 0.24), Vector2(0.19, 0.33),
						Vector2(0.15, Geometry.ANCHOR_HEIGHT - 0.18),
						Vector2(0.15, Geometry.ANCHOR_HEIGHT - 0.015),
						Vector2(0.09, Geometry.ANCHOR_HEIGHT - 0.015)])
					z_input_post_mesh = ProductionVisuals.prism_mesh(cheek, 0.10, 0.004)
				_press_fixed(parent, "PressInputPost" + suffix, "Post",
					z_input_post_mesh, at)

	static func _collector_fixed(parent: Node3D, name_value: String, role: String,
			mesh_value: Mesh, at: Vector3, basis_value: Basis = Basis.IDENTITY) -> void:
		var part := MeshInstance3D.new()
		part.name = name_value
		part.position = at
		part.basis = basis_value
		part.mesh = mesh_value
		part.material_override = ProductionTransmissionFinish.material("worked", Color("878d7f"), 0.85, 0.42) \
			if role == "Bearing" else ProductionCoating.material(Color("394a44"))
		part.set_meta("collector_input_role", role)
		parent.add_child(part)

	static func mount_collector_bearings(parent: Node3D, axis: Vector3) -> void:
		if collector_bearing_mesh == null:
			collector_bearing_mesh = ProductionVisuals.turned_mesh(PackedVector2Array([
				Vector2(0.087, -0.010), Vector2(0.089, -0.015), Vector2(0.096, -0.015),
				Vector2(0.100, -0.011), Vector2(0.100, 0.011), Vector2(0.096, 0.015),
				Vector2(0.089, 0.015), Vector2(0.087, 0.010), Vector2(0.087, -0.010)]))
		var along_x := axis == Vector3.RIGHT
		for side in [-1.0, 1.0]:
			var suffix := "Left" if side < 0 else "Right"
			var at: Vector3 = axis * float(side) * 0.66
			_collector_fixed(parent, "CollectorInputBearing" + suffix, "Bearing", collector_bearing_mesh,
				at + Vector3.UP * Geometry.ANCHOR_HEIGHT, Basis(Quaternion(Vector3.UP, axis)))
			# The post and skid foot touch below the bearing. Their narrow axial
			# faces remain outboard of the stock bed at both confirmed input axes.
			_collector_fixed(parent, "CollectorInputPost" + suffix, "Post",
				ProductionVisuals.box_mesh(Vector3(0.08, 0.50, 0.16) if along_x else Vector3(0.16, 0.50, 0.08)),
				axis * float(side) * 0.675 + Vector3.UP * 0.49)
			_collector_fixed(parent, "CollectorInputFoot" + suffix, "Foot",
				ProductionVisuals.box_mesh(Vector3(0.26, 0.10, 0.20) if along_x else Vector3(0.20, 0.10, 0.26)),
				axis * float(side) * 0.58 + Vector3.UP * 0.20)
