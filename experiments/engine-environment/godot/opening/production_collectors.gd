extends RefCounted
## Render resources only; no scene controller or simulation authority.
const ProductionCoating = preload("res://opening/production_surfaces.gd").ProductionCoating
const ProductionMeshAssembly = preload("res://opening/production_surfaces.gd").ProductionMeshAssembly
const ProductionTransmissionFinish = preload("res://opening/production_surfaces.gd").ProductionTransmissionFinish
const ProductionVisuals = preload("res://opening/production_surfaces.gd").ProductionVisuals

class ProductionCollectorArt:
	extends RefCounted
	## Original rigid casting kit. These meshes never define work or collision.
	static func cheek_profile(right: bool) -> PackedVector2Array:
		var points := PackedVector2Array([Vector2(-0.65, 0.24), Vector2(-0.65, 0.40),
			Vector2(-0.62, 0.47), Vector2(-0.62, 1.31), Vector2(-0.58, 1.48),
			Vector2(-0.49, 1.49), Vector2(-0.48, 1.44), Vector2(-0.50, 1.36),
			Vector2(-0.50, 0.62), Vector2(-0.40, 0.48), Vector2(-0.38, 0.38), Vector2(-0.38, 0.24)])
		if right:
			for n in range(points.size()):
				points[n].x = -0.39 - points[n].x
		return points


	static func _part(parent: Node3D, role: String, mesh: Mesh, at: Vector3,
			finish: StandardMaterial3D) -> MeshInstance3D:
		var part := MeshInstance3D.new()
		part.name = role
		part.mesh = mesh
		part.position = at
		part.material_override = finish
		part.set_meta("collector_frame_role", role)
		parent.add_child(part)
		return part

	static func mount(parent: Node3D, color: Color) -> void:
		var frame := Node3D.new()
		frame.name = "CollectorCastFrame"
		parent.add_child(frame)
		var paint := ProductionCoating.material(color)
		for right in [false, true]:
			_part(frame, "CastCheekRight" if right else "CastCheekLeft",
				ProductionVisuals.prism_mesh(cheek_profile(right), 0.18, 0.008), Vector3(0, 0, -0.40), paint)
		var housing := PackedVector2Array([Vector2(-0.62, 0.24), Vector2(0.23, 0.24),
			Vector2(0.23, 0.84), Vector2(0.12, 1.02), Vector2(-0.50, 1.02), Vector2(-0.62, 0.84)])
		_part(frame, "CastLowerHousing", ProductionVisuals.prism_mesh(housing, 0.14, 0.012),
			Vector3(0, 0, -0.44), ProductionCoating.material(color.darkened(0.09)))
		# A neutral service cover has a folded lower return, angled shoulders and
		# a shallow crown. Its broad roof is a formed part, not a bright flat box.
		var hood := PackedVector2Array([Vector2(-0.65, 1.38), Vector2(0.26, 1.38),
			Vector2(0.26, 1.42), Vector2(0.22, 1.42), Vector2(0.22, 1.47),
			Vector2(0.15, 1.51), Vector2(-0.19, 1.54), Vector2(-0.53, 1.51),
			Vector2(-0.62, 1.47), Vector2(-0.62, 1.42), Vector2(-0.65, 1.42)])
		_part(frame, "CastUpperHood", ProductionVisuals.prism_mesh(hood, 0.64, 0.012),
			Vector3(0, 0, -0.25), ProductionCoating.material(Color("394f59")))
		var hanger := PackedVector2Array([Vector2(-0.26, 1.21), Vector2(-0.18, 1.21),
			Vector2(-0.15, 1.32), Vector2(-0.13, 1.43), Vector2(-0.31, 1.43), Vector2(-0.29, 1.32)])
		_part(frame, "BearingHanger", ProductionVisuals.prism_mesh(hanger, 0.07, 0.007), Vector3(0, 0, 0.045), paint)
		var bearing := PackedVector2Array([Vector2(0.109, -0.025), Vector2(0.125, -0.025),
			Vector2(0.14, -0.015), Vector2(0.14, 0.015), Vector2(0.125, 0.025),
			Vector2(0.109, 0.025), Vector2(0.109, -0.025)])
		var housing_part := _part(frame, "FixedBearingHousing", ProductionVisuals.turned_mesh(bearing),
			Vector3(-0.22, 1.1, 0.045), paint)
		housing_part.basis = Basis(Quaternion(Vector3.UP, Vector3.BACK))
		var liner := PackedVector2Array([Vector2(0.095, -0.014), Vector2(0.109, -0.014),
			Vector2(0.109, 0.014), Vector2(0.095, 0.014), Vector2(0.095, -0.014)])
		var liner_part := _part(frame, "FixedBearingLiner", ProductionVisuals.turned_mesh(liner),
			Vector3(-0.22, 1.1, 0.045), ProductionTransmissionFinish.material("worked", Color("a6b4af"), 0.85, 0.38))
		liner_part.basis = housing_part.basis

class ProductionFeedSleeveArt:
	extends RefCounted
	## Render the existing confirmed feed link. No stock, transfer or power rule.
	const CACHE_LENGTH_STEP := 0.00001
	const MINIMUM_RENDER_SPAN := 0.28
	const FLOOR_HEIGHT := 0.09
	static var bolt_mesh: CylinderMesh
	static var marking: StandardMaterial3D

	static func _part(parent: Node3D, role: String, suffix: String, mesh: Mesh,
			at: Vector3, orientation: Basis, finish: Material) -> MeshInstance3D:
		var part := MeshInstance3D.new()
		part.name = role + suffix
		part.set_meta("feed_sleeve_role", role)
		part.mesh = mesh
		part.position = at
		part.basis = orientation
		part.material_override = finish
		parent.add_child(part)
		return part

	static func mount(parent: Node3D, start: Vector3, finish: Vector3) -> bool:
		var offset: Vector3 = finish - start
		var span: float = offset.length()
		if not start.is_finite() or not finish.is_finite() or not offset.is_finite() \
				or not is_finite(span) or offset.y != 0 or span < MINIMUM_RENDER_SPAN:
			return false
		# Cache equivalent render lengths despite float packing at different
		# grid positions. This does not round a native pose, command or reach.
		var length: float = snappedf(span, CACHE_LENGTH_STEP)
		var direction: Vector3 = offset / span
		var across := Vector3(direction.z, 0, -direction.x)
		var channel := PackedVector2Array([Vector2(-0.292, -0.012), Vector2(0.292, -0.012),
			Vector2(0.292, 0.07), Vector2(0.28, 0.07), Vector2(0.28, 0),
			Vector2(-0.28, 0), Vector2(-0.28, 0.07), Vector2(-0.292, 0.07)])
		var cuff := PackedVector2Array([Vector2(-0.306, -0.026), Vector2(0.306, -0.026),
			Vector2(0.306, 0.07), Vector2(0.292, 0.07), Vector2(0.292, -0.012),
			Vector2(-0.292, -0.012), Vector2(-0.292, 0.07), Vector2(-0.306, 0.07)])
		var arrow := PackedVector2Array([Vector2(-0.09, -0.03), Vector2(-0.025, -0.03),
			Vector2(-0.025, -0.12), Vector2(0.025, -0.12), Vector2(0.025, -0.03),
			Vector2(0.09, -0.03), Vector2(0, 0.07)])
		var worked := ProductionTransmissionFinish.material("worked", Color("929e91"), 0.85, 0.52)
		var cast := ProductionTransmissionFinish.material("cast", Color("465a60"), 0.85, 0.55)
		var hardware := ProductionTransmissionFinish.material("worked", Color("a6b4af"), 0.85, 0.38)
		if worked == null or cast == null or hardware == null:
			return false
		if bolt_mesh == null:
			bolt_mesh = CylinderMesh.new()
			bolt_mesh.top_radius = 0.0115
			bolt_mesh.bottom_radius = 0.0115
			bolt_mesh.height = 0.014
			bolt_mesh.radial_segments = 6
		if marking == null:
			marking = StandardMaterial3D.new()
			marking.albedo_color = Color("e2c48b")
			marking.metallic = 0
			marking.roughness = 0.85
		parent.position = (start + finish) / 2.0
		parent.basis = Basis(across, Vector3.UP, direction)
		parent.set_meta("feed_sleeve", true)
		parent.set_meta("render_span", length)
		_part(parent, "FeedChannel", "", ProductionVisuals.prism_mesh(channel, length, 0.001),
			Vector3(0, FLOOR_HEIGHT, 0), Basis.IDENTITY, worked)
		for end in [-1.0, 1.0]:
			var suffix := "N" if end < 0 else "P"
			var z: float = end * (length / 2.0 - 0.0225)
			_part(parent, "FeedCuff", suffix, ProductionVisuals.prism_mesh(cuff, 0.045, 0.001),
				Vector3(0, FLOOR_HEIGHT, z), Basis.IDENTITY, cast)
			for side in [-1.0, 1.0]:
				_part(parent, "FeedBolt", suffix + ("N" if side < 0 else "P"), bolt_mesh,
					Vector3(side * 0.313, FLOOR_HEIGHT + 0.035, z),
					Basis(Quaternion(Vector3.UP, Vector3.RIGHT * side)), hardware)
		_part(parent, "FeedDirection", "", ProductionVisuals.prism_mesh(arrow, 0.002, 0.0002),
			Vector3(0, FLOOR_HEIGHT + 0.001, length * 0.2), Basis(Vector3.RIGHT, PI / 2), marking)
		return true

class ProductionCollectorFeedArt:
	extends RefCounted
	## Formed guides sit on the literal stock bed. They carry no material state.
	static var rail_mesh: ArrayMesh
	static var clamp_mesh: ArrayMesh

	static func _part(parent: Node3D, role: String, mesh: Mesh, at: Vector3,
			finish: StandardMaterial3D, scale: Vector3 = Vector3.ONE) -> void:
		var part := MeshInstance3D.new()
		part.name = role
		part.set_meta("collector_feed_role", role)
		part.mesh = mesh
		part.position = at
		part.scale = scale
		part.material_override = finish
		parent.add_child(part)

	static func mount(parent: Node3D, color: Color) -> bool:
		var paint := ProductionCoating.material(color.darkened(0.13))
		var steel := ProductionTransmissionFinish.material("worked", Color("9caaa5"), 0.85, 0.42)
		if paint == null or steel == null:
			return false
		if rail_mesh == null:
			# The contact plane stays at the original bed top, y = 0.56.
			# A tapered end and folded upper edge avoid a floating box silhouette.
			var section := PackedVector2Array([Vector2(-0.525, 0.56),
				Vector2(0.625, 0.56), Vector2(0.625, 0.585),
				Vector2(0.575, 0.615), Vector2(0.50, 0.64),
				Vector2(-0.45, 0.64), Vector2(-0.525, 0.605)])
			rail_mesh = ProductionVisuals.prism_mesh(section, 0.06, 0.003)
			clamp_mesh = ProductionVisuals.box_mesh(Vector3(0.11, 0.07, 0.13))
		var assembly := Node3D.new()
		assembly.name = "CollectorFeedGuides"
		parent.add_child(assembly)
		for side in [-1.0, 1.0]:
			var z: float = side * 0.335
			_part(assembly, "FormedGuide", rail_mesh, Vector3(0, 0, z), paint)
			# Clamp feet overlap both the rail and the unchanged bed edge.
			# Neither claims a new support or collision volume.
			for x in [-0.42, 0.42]:
				_part(assembly, "GuideClamp", clamp_mesh, Vector3(x, 0.53, z), paint)
				_part(assembly, "ClampHead", ProductionVisuals.fastener_head_mesh(),
					Vector3(x, 0.6445, z), steel, Vector3.ONE * 0.38)
		return true

class ProductionCollectorOutputArt:
	extends RefCounted
	## The intake stays aimed at the fixed seam. This passive cassette follows
	## only the native material-output quarter turn inside the machine body.
	static func _part(parent: Node3D, role: String, size: Vector3, at: Vector3,
			finish: Material) -> void:
		var part := MeshInstance3D.new()
		part.name = role
		part.mesh = ProductionVisuals.box_mesh(size)
		part.position = at
		part.material_override = finish
		part.set_meta("collector_output_role", role)
		parent.add_child(part)

	static func mount(parent: Node3D, rotation: int) -> void:
		var cassette := Node3D.new()
		cassette.name = "CollectorOutputCassette"
		cassette.rotation.y = -float(posmod(rotation, 4)) * PI / 2.0
		parent.add_child(cassette)
		var steel := ProductionTransmissionFinish.material("worked", Color("a6b4af"), 0.85, 0.4)
		var paint := ProductionCoating.material(Color("58634c"))
		if steel == null or paint == null:
			return
		# The inner floor meets the original stock bed at y = 0.56 and ends
		# inside the confirmed 0.725 m half-width. An open end remains open
		# until the native material link supplies a real neighboring route.
		_part(cassette, "OutletFloor", Vector3(0.48, 0.035, 0.38),
			Vector3(0.45, 0.5675, 0), steel)
		for side in [-1.0, 1.0]:
			_part(cassette, "OutletSideLeft" if side < 0 else "OutletSideRight", Vector3(0.48, 0.105, 0.035),
				Vector3(0.45, 0.635, side * 0.21), paint)
		_part(cassette, "OutletLip", Vector3(0.055, 0.025, 0.46),
			Vector3(0.69, 0.60, 0), steel)

class ProductionCollectorToolingArt:
	extends RefCounted
	## Passive rigid tooling. The existing cutter rows and presenter own its pose.
	static var meshes: Dictionary = {}

	static func drum_mesh() -> ArrayMesh:
		if not meshes.has("drum"):
			var section := PackedVector2Array([
				Vector2(0.085, -0.17), Vector2(0.218, -0.17), Vector2(0.228, -0.164),
				Vector2(0.24, -0.15), Vector2(0.24, -0.13), Vector2(0.228, -0.12),
				Vector2(0.228, 0.12), Vector2(0.24, 0.13), Vector2(0.24, 0.15),
				Vector2(0.228, 0.164), Vector2(0.218, 0.17), Vector2(0.085, 0.17), Vector2(0.085, -0.17)])
			meshes.drum = ProductionVisuals.turned_mesh(section)
		return meshes.drum

	static func hub_mesh() -> ArrayMesh:
		if not meshes.has("hub"):
			var section := PackedVector2Array([
				Vector2(0, -0.04), Vector2(0.078, -0.04), Vector2(0.085, -0.036),
				Vector2(0.085, -0.020), Vector2(0.078, -0.014), Vector2(0.078, -0.006),
				Vector2(0.085, 0), Vector2(0.085, 0.039), Vector2(0.083, 0.04), Vector2(0, 0.04)])
			meshes.hub = ProductionVisuals.turned_mesh(section)
		return meshes.hub

	static func flute_mesh() -> ArrayMesh:
		if meshes.has("flute"):
			return meshes.flute
		var holder := PackedVector2Array([
			Vector2(-0.02, -0.0225), Vector2(0.02, -0.0225), Vector2(0.02, 0.0025),
			Vector2(0.012, 0.0075), Vector2(-0.012, 0.0075), Vector2(-0.02, 0.0025)])
		var insert := PackedVector2Array([
			Vector2(-0.012, 0.0075), Vector2(0.012, 0.0075), Vector2(0.02, 0.0175),
			Vector2(0.014, 0.0225), Vector2(-0.014, 0.0225), Vector2(-0.02, 0.0175)])
		var mesh := ArrayMesh.new()
		ProductionMeshAssembly.append_surface(mesh, "InsertHolder", [[ProductionVisuals.prism_mesh(holder, 0.29, 0.001), Transform3D.IDENTITY]])
		ProductionMeshAssembly.append_surface(mesh, "CuttingInsert", [[ProductionVisuals.prism_mesh(insert, 0.27, 0.0006), Transform3D.IDENTITY]])
		var heads: Array = []
		for z in [-0.14, 0.14]:
			heads.append([ProductionVisuals.fastener_head_mesh(),
				Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.12), Vector3(0, 0.00894, z))])
		ProductionMeshAssembly.append_surface(mesh, "RetainingHeads", heads)
		meshes.flute = mesh
		return mesh

	static func mount_body(drum: MeshInstance3D, hub: MeshInstance3D) -> void:
		var dark := ProductionTransmissionFinish.material("worked", Color("465a60"), 0.85, 0.4)
		var steel := ProductionTransmissionFinish.material("worked", Color("a6b4af"), 0.85, 0.4)
		if dark == null or steel == null:
			return
		drum.mesh = drum_mesh()
		drum.material_override = dark
		drum.set_meta("collector_tooling_role", "BoredDrum")
		hub.mesh = hub_mesh()
		hub.material_override = steel
		hub.set_meta("collector_tooling_role", "SteppedHub")

	static func mount_flute(flute: MeshInstance3D) -> void:
		var holder := ProductionTransmissionFinish.material("worked", Color("465a60"), 0.85, 0.4)
		var insert := ProductionTransmissionFinish.material("worked", Color("b8c3bb"), 0.9, 0.3)
		var hardware := ProductionTransmissionFinish.material("worked", Color("778b8c"), 0.85, 0.4)
		if holder == null or insert == null or hardware == null:
			return
		flute.mesh = flute_mesh()
		flute.material_override = null
		flute.set_surface_override_material(0, holder)
		flute.set_surface_override_material(1, insert)
		flute.set_surface_override_material(2, hardware)
		flute.set_meta("collector_tooling_role", "FittedInsert")

class ProductionCollectorServiceArt:
	extends RefCounted
	## Fixed rear access artwork. No service action, state or collision owner.
	static var meshes: Dictionary = {}

	static func _outline(width: float, height: float, corner: float) -> PackedVector2Array:
		var x := width / 2.0
		var y := height / 2.0
		return PackedVector2Array([Vector2(-x + corner, -y), Vector2(x - corner, -y),
			Vector2(x, -y + corner), Vector2(x, y - corner), Vector2(x - corner, y),
			Vector2(-x + corner, y), Vector2(-x, y - corner), Vector2(-x, -y + corner)])

	static func _prepare() -> void:
		if not meshes.is_empty():
			return
		meshes.gasket = ProductionVisuals.prism_mesh(_outline(0.662, 0.522, 0.032), 0.003, 0.0004)
		meshes.panel = ProductionVisuals.prism_mesh(_outline(0.64, 0.50, 0.028), 0.018, 0.002)
		var hardware := ArrayMesh.new()
		var poses: Array[Transform3D] = []
		var orientation := Basis(Quaternion(Vector3.UP, Vector3.FORWARD)).scaled(Vector3.ONE * 0.45)
		for x in [-0.255, 0.255]:
			for y in [-0.19, 0.19]:
				poses.append(Transform3D(orientation, Vector3(x, y, 0)))
		ProductionMeshAssembly.append_hardware(hardware, poses)
		meshes.hardware = hardware
		meshes.frame_leaf = ProductionVisuals.box_mesh(Vector3(0.06, 0.07, 0.006))
		meshes.panel_leaf = ProductionVisuals.box_mesh(Vector3(0.05, 0.07, 0.006))
		var pin := CylinderMesh.new()
		pin.top_radius = 0.011
		pin.bottom_radius = 0.011
		pin.height = 0.09
		pin.radial_segments = 16
		meshes.hinge_pin = pin
		meshes.latch_back = ProductionVisuals.box_mesh(Vector3(0.10, 0.15, 0.006))
		meshes.latch_stand = ProductionVisuals.box_mesh(Vector3(0.018, 0.022, 0.036))
		meshes.latch_grip = ProductionVisuals.box_mesh(Vector3(0.025, 0.13, 0.018))
		meshes.latch_keeper = ProductionVisuals.box_mesh(Vector3(0.055, 0.08, 0.006))
		meshes.latch_tongue = ProductionVisuals.box_mesh(Vector3(0.10, 0.025, 0.026))

	static func _fixed(parent: Node3D, role: String, mesh: Mesh, at: Vector3,
			finish: Material) -> void:
		var part := MeshInstance3D.new()
		part.name = role
		part.set_meta("collector_service_role", role)
		part.mesh = mesh
		part.position = at
		part.material_override = finish
		parent.add_child(part)

	static func mount(parent: Node3D, color: Color) -> void:
		_prepare()
		var paint := ProductionCoating.material(color.darkened(0.14))
		var steel := ProductionTransmissionFinish.material("worked", Color("b8c3bb"), 0.85, 0.38)
		var gasket := ProductionVisuals.material(Color("1c2424"), 0.0, 0.95)
		for row in [["RearServiceGasket", "gasket", -0.5115, gasket],
			["RearServicePanel", "panel", -0.522, paint], ["RearServiceHardware", "hardware", -0.531, steel]]:
			var part := MeshInstance3D.new()
			part.name = row[0]
			part.set_meta("collector_service_role", row[1])
			part.mesh = meshes[row[1]]
			part.position = Vector3(-0.22, 0.67, row[2])
			part.material_override = row[3]
			parent.add_child(part)
		# Two fixed leaves visibly connect the removable panel to the casting.
		# The pin bridges their different front planes; none is a service action.
		for y in [0.52, 0.79]:
			var suffix := "Lower" if y < 0.67 else "Upper"
			_fixed(parent, "RearServiceFrameLeaf" + suffix, meshes.frame_leaf,
				Vector3(-0.575, y, -0.513), steel)
			_fixed(parent, "RearServicePanelLeaf" + suffix, meshes.panel_leaf,
				Vector3(-0.51, y, -0.534), steel)
			_fixed(parent, "RearServiceHingePin" + suffix, meshes.hinge_pin,
				Vector3(-0.545, y, -0.525), steel)
		# A visible pull and fixed keeper make the opposite edge read as closed.
		_fixed(parent, "RearServiceLatchBack", meshes.latch_back, Vector3(0.015, 0.67, -0.534), steel)
		for y in [0.615, 0.725]:
			_fixed(parent, "RearServiceLatchStand" + ("Low" if y < 0.67 else "High"),
				meshes.latch_stand, Vector3(0.015, y, -0.55), steel)
		_fixed(parent, "RearServiceLatchGrip", meshes.latch_grip, Vector3(0.015, 0.67, -0.574), steel)
		_fixed(parent, "RearServiceLatchKeeper", meshes.latch_keeper, Vector3(0.145, 0.67, -0.513), steel)
		_fixed(parent, "RearServiceLatchTongue", meshes.latch_tongue, Vector3(0.11, 0.67, -0.524), steel)
