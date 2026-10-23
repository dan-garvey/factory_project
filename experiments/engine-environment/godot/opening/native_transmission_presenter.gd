extends Node3D
## Confirmed geometry/rates with cosmetic angles only. No simulation clock,
## saved/contact phase, material operation or actor collider.
const Geometry = preload("res://opening/site_geometry.gd")
const Assets = preload("res://opening/native_transmission_assets.gd")
const Items = preload("res://opening/workpiece_item_assets.gd")
const NativeModel = preload("res://opening/native_model.gd")
const Finish = preload("res://opening/opening.gd").ProductionTransmissionFinish
const Visuals = preload("res://opening/opening.gd").ProductionVisuals
const WheelArt = preload("res://opening/opening.gd").ProductionWheelArt
const ClampBody = preload("res://opening/assets/collector-clamp/collector_clamp.gltf")
const UNIT := Geometry.PITCH / 4.0
## The native lane moves one horizontal tile per 0.45-second tick at rate 1.
## Its pulley rim must travel the same distance in that time.
const VISUAL_RADIANS_PER_SECOND := Geometry.PITCH / (Assets.SPAN_OUTER_RADIUS * 0.45)
const BELT_SUBTICKS_PER_TILE := 4096.0 # Matches the native material lane's fixed-point denominator.
const CARGO_TICK_SECONDS := 0.45
const INCLINED_SUBTICKS_PER_TICK := 2896.0 # Native lane advances one horizontal tile of surface distance.
const GEAR_BATCH_THRESHOLD := 4

var _host: WeakRef
var _view_key: Variant = null
var _native_view_context := ""
var _native_view_revision: Variant = null
var _cargo_keys: Dictionary = {}
var _cargo_elapsed: Dictionary = {}
var _cargo_anchors: Array[Node3D] = []
var _motion_context := ""
var _motion_revision: Variant = null
var _generations: Dictionary = {}
var _visual_rates: Dictionary = {}
var _visual_angles: Dictionary = {}
var _visual_rotations: Dictionary = {}
var _gear_batches: Dictionary = {}
var _batched_gear_ids: Dictionary = {}
var _gear_anchor_cache: Dictionary = {}
var _moving_anchors: Array[Node3D] = []
var _direction_meshes: Dictionary = {}
var _support_meshes: Dictionary = {}
static var _relay_shells: Dictionary = {}
static var _cutting_blade_meshes: Dictionary = {}
static var _receiver_pan_mesh: ArrayMesh

func configure(host: Object) -> void:
	_host = weakref(host)
	_view_key = null
	_native_view_context = ""
	_native_view_revision = null
	_clear_motion()
	refresh()

func _clear(retained_nodes: Dictionary = {}) -> void:
	_cargo_keys.clear()
	_cargo_elapsed.clear()
	_cargo_anchors.clear()
	_gear_batches.clear()
	_batched_gear_ids.clear()
	_gear_anchor_cache.clear()
	_native_view_context = ""
	_native_view_revision = null
	_moving_anchors.clear()
	for child in get_children():
		if not retained_nodes.has(child.get_instance_id()):
			child.free()

func _clear_motion() -> void:
	_motion_context = ""
	_motion_revision = null
	_generations.clear()
	_visual_rates.clear()
	_visual_angles.clear()
	_visual_rotations.clear()

func _sync_motion(snapshot: Dictionary) -> void:
	var context: Variant = snapshot.get("context")
	if typeof(context) != TYPE_STRING or context.is_empty():
		_clear_motion()
		return
	if _motion_context != context:
		_clear_motion()
		_motion_context = context
	var current: Dictionary = {}
	for group: String in ["entities", "transmission_parts"]:
		var parts: Variant = snapshot.get(group, {})
		if not parts is Dictionary:
			continue
		for id: Variant in parts:
			var part: Variant = parts[id]
			if typeof(id) != TYPE_STRING or not part is Dictionary or typeof(part.get("generation")) != TYPE_INT or part.generation < 1:
				continue
			current[id] = part.generation
	for id: Variant in _visual_angles.keys():
		if not current.has(id) or current[id] != _generations.get(id):
			_visual_angles.erase(id)
			_visual_rotations.erase(id)
	_generations = current
	# Native revisions freeze confirmed motion. Keep the active rates once per
	# projection instead of parsing every part's motion each render frame.
	_visual_rates.clear()
	var motions: Variant = snapshot.get("motion", {})
	if motions is Dictionary:
		for id: String in current:
			var rate := signed_rate(motions.get(id))
			if rate != 0.0:
				_visual_rates[id] = rate
	_motion_revision = snapshot.get("revision")

static func signed_rate(motion: Variant) -> float:
	if not motion is Dictionary or motion.get("state") != "rotating" or typeof(motion.get("numerator")) != TYPE_INT or typeof(motion.get("denominator")) != TYPE_INT or motion.denominator <= 0:
		return 0.0
	return float(motion.numerator) / float(motion.denominator)

func visual_angle(id: String) -> float:
	return float(_visual_angles.get(id, 0.0))

func visual_rotation(id: String) -> float:
	return float(_visual_rotations.get(id, 0.0))

func _apply_angles(update_gears := true) -> void:
	for child: Node3D in _moving_anchors:
		if child.has_meta("belt_shaft"):
			var loop := child.get_node_or_null("BeltLoop") as MeshInstance3D
			if loop != null and loop.material_override is StandardMaterial3D:
				var finish := loop.material_override as StandardMaterial3D
				var offset := float(child.get_meta("belt_uv_origin")) + visual_rotation(str(child.get_meta("belt_shaft"))) * float(child.get_meta("belt_uv_factor"))
				finish.uv1_offset.x = fposmod(offset, 1.0)
		if not child.has_meta("axis"):
			if child.has_meta("relay_static"):
				var relay_id: String = str(child.get_meta("entity", ""))
				var relay_angle := visual_angle(relay_id)
				for port: Node in child.get_children():
					if port is Node3D and port.has_meta("relay_port_axis"):
						port.basis = axis_basis(int(port.get_meta("relay_port_axis"))) * \
							Basis(Vector3.UP, relay_angle * float(port.get_meta("relay_factor")))
			continue
		var id: String = str(child.get_meta("entity", ""))
		var angle := visual_angle(id)
		child.basis = axis_basis(int(child.get_meta("axis"))) * Basis(Vector3.UP, angle)
		var arrow := child.get_node_or_null("ConfirmedDirection")
		if arrow != null:
			# Keep the signed-rate annotation fixed while its rotor turns.
			arrow.rotation.y = -angle
	if update_gears:
		for batch: Dictionary in _gear_batches.values():
			var mesh: MultiMesh = batch.mesh
			var ids: Array = batch.ids
			var bases: Array = batch.bases
			var origins: Array = batch.origins
			var last_angles: Array[float] = batch.last_angles
			for index in ids.size():
				var angle := float(_visual_angles.get(ids[index], 0.0))
				if angle == last_angles[index]:
					continue
				var basis: Basis = bases[index] * Basis(Vector3.UP, angle)
				mesh.set_instance_transform(index, Transform3D(basis, origins[index]))
				last_angles[index] = angle
			batch.last_angles = last_angles

func advance_visual_motion(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0 or _host == null or not is_instance_valid(_host.get_ref()):
		return
	var host: Object = _host.get_ref()
	# The owning view handles shared freshness. Pending construction does not
	# change a confirmed drive; a lost connection cannot keep inventing motion.
	if not host.has_method("_can_present_confirmed_motion") or not host.call("_can_present_confirmed_motion"):
		return
	var snapshot: Variant = host.get("state")
	if not snapshot is Dictionary or not snapshot.get("motion") is Dictionary:
		return
	# A machine can be rebuilt before the next presenter refresh. Catch that
	# addition here; ordinary replacement projections carry a new revision.
	var identity_count := 0
	for group: String in ["entities", "transmission_parts"]:
		var parts: Variant = snapshot.get(group)
		if parts is Dictionary:
			identity_count += parts.size()
	if _motion_context != snapshot.get("context", "") or _motion_revision != snapshot.get("revision") or identity_count != _generations.size():
		_sync_motion(snapshot)
	var changed_gears := false
	# Synthetic callers can mutate one revision in place, so they retain the
	# direct lookup. Native World increments revision on every changed state.
	var native_motion := host.get("model") is NativeModel
	var rates: Dictionary = _visual_rates if native_motion else _generations
	for id: String in rates:
		var rate: float = rates[id] if native_motion else signed_rate(snapshot.motion.get(id))
		if rate != 0.0:
			var step := delta * rate * VISUAL_RADIANS_PER_SECOND
			var rotation := visual_rotation(id) + step
			if not is_finite(step) or not is_finite(rotation):
				continue
			_visual_rotations[id] = rotation
			_visual_angles[id] = wrapf(visual_angle(id) + step, -PI, PI)
			changed_gears = changed_gears or _batched_gear_ids.has(id)
	_apply_angles(changed_gears)
	if not _cargo_anchors.is_empty():
		_advance_belt_cargo(delta, snapshot)

static func axis_basis(axis: int) -> Basis:
	match axis:
		0: return Basis(Vector3.DOWN, Vector3.RIGHT, Vector3.BACK)
		2: return Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN)
	return Basis.IDENTITY

static func world_center(center: Array) -> Vector3:
	return Vector3(center[0] * UNIT, Geometry.ANCHOR_HEIGHT + center[1] * UNIT, center[2] * UNIT)

func _valid_part(part: Variant) -> bool:
	if not part is Dictionary or part.get("kind") not in ["gear", "shaft", "gearbox", "vertical_gearbox", "chain_drive"]:
		return false
	if typeof(part.get("axis")) != TYPE_INT or part.axis not in [0, 1, 2]:
		return false
	var center: Variant = part.get("center")
	if not center is Array or center.size() != 3:
		return false
	for value: Variant in center:
		if typeof(value) != TYPE_INT or value < -1048576 or value > 1048576:
			return false
	if part.kind == "gearbox" and part.axis != 1:
		return false
	if part.kind == "vertical_gearbox" and part.axis == 1:
		return false
	if part.kind == "chain_drive":
		return typeof(part.get("relay_axis")) == TYPE_INT and part.relay_axis in [0, 1, 2] and part.relay_axis != part.axis
	if part.kind in ["gearbox", "vertical_gearbox"]:
		return true
	var size: Variant = part.get("teeth" if part.kind == "gear" else "half_span")
	return typeof(size) == TYPE_INT and size > 0 and size <= 256

func _support_point(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for coordinate: Variant in value:
		if typeof(coordinate) != TYPE_FLOAT or not is_finite(coordinate):
			return false
	return true

func _confirmed_support(id: String, part: Dictionary) -> Node3D:
	var support: Variant = part.get("support")
	if not support is Dictionary or not _support_point(support.get("foot")) or not _support_point(support.get("bearing")):
		return null
	var foot := Vector3(support.foot[0], support.foot[1], support.foot[2])
	var bearing := Vector3(support.bearing[0], support.bearing[1], support.bearing[2])
	if bearing.y <= foot.y or bearing.y - foot.y > 9.0:
		return null
	var frame := Node3D.new()
	frame.name = "FixedSupport"
	frame.set_meta("supported_entity", id)
	add_child(frame)
	var cast := Finish.material("cast", Color("82908d"), 0.78, 0.48)
	var worked := Finish.material("worked", Color("bac5c0"), 0.86, 0.32)
	var dark := Finish.material("cast", Color("424e4c"), 0.72, 0.53)
	_support_box(frame, "FootShoe", foot + Vector3.UP * 0.06, Vector3(0.34, 0.12, 0.34), dark)
	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			var bolt := _support_cylinder(frame, "FootAnchor", 0.018, 0.015, worked)
			bolt.position = foot + Vector3(x_sign * 0.125, 0.128, z_sign * 0.125)
	var height: float = bearing.y - 0.24 - foot.y
	if height <= 0.0:
		remove_child(frame)
		frame.free()
		return null
	var across: Vector3 = Vector3.FORWARD if part.axis == 0 else Vector3.RIGHT
	var side: Vector3 = Vector3.UP.cross(across)
	# The visual frame stays near the one native-confirmed support point. These
	# braces do not claim extra terrain seats, clearance or structural strength.
	if height < 0.48:
		_support_box(frame, "CompactPedestal", foot + Vector3.UP * height * 0.5,
			Vector3(0.18, height, 0.18), cast)
	else:
		var bays: int = ceili(height / 1.15)
		var bay_height: float = height / float(bays)
		for rail_sign in [-1.0, 1.0]:
			var rail_offset: Vector3 = across * float(rail_sign) * 0.09
			for bay in range(bays):
				var low: Vector3 = foot + Vector3.UP * float(bay) * bay_height + rail_offset
				var high: Vector3 = low + Vector3.UP * bay_height
				_support_beam(frame, "CastUpright", low, high, 0.065, cast)
		for bay in range(bays):
			var low: Vector3 = foot + Vector3.UP * float(bay) * bay_height - side * 0.07
			_support_beam(frame, "RearSpine", low, low + Vector3.UP * bay_height, 0.06, dark)
		for bay in range(bays):
			var low_y: float = float(bay) * bay_height
			var high_y: float = float(bay + 1) * bay_height
			var low: Vector3 = foot + Vector3.UP * low_y - across * 0.09
			var high: Vector3 = foot + Vector3.UP * high_y + across * 0.09
			if bay % 2 == 1:
				low = foot + Vector3.UP * low_y + across * 0.09
				high = foot + Vector3.UP * high_y - across * 0.09
			_support_beam(frame, "DiagonalBrace", low, high, 0.045, worked)
			_support_beam(frame, "BayTie", foot + Vector3.UP * high_y - across * 0.09,
				foot + Vector3.UP * high_y + across * 0.09, 0.05, worked)
			_support_beam(frame, "SideBrace", foot + Vector3.UP * low_y - side * 0.07,
				high, 0.035, cast)
	if not is_equal_approx(foot.x, bearing.x) or not is_equal_approx(foot.z, bearing.z):
		_support_beam(frame, "BearingArm", Vector3(foot.x, bearing.y - 0.24, foot.z),
			bearing - Vector3.UP * 0.24, 0.095, worked)
	else:
		_support_box(frame, "BearingArm", bearing - Vector3.UP * 0.24, Vector3(0.31, 0.095, 0.31), worked)
	_support_box(frame, "BearingSaddle", bearing - Vector3.UP * 0.20, Vector3(0.31, 0.08, 0.31), cast)
	var socket := _support_cylinder(frame, "BearingHousing", 0.16, 0.23, dark)
	socket.position = bearing
	socket.basis = axis_basis(part.axis)
	var rim := _support_cylinder(frame, "MachinedBearingRim", 0.185, 0.045, worked)
	rim.position = bearing + axis_basis(part.axis).y * 0.13
	rim.basis = socket.basis
	return frame

func _support_style(part: Dictionary) -> String:
	var support: Variant = part.get("support")
	if not support is Dictionary or not _support_point(support.get("foot")) or not _support_point(support.get("bearing")):
		return ""
	var center := world_center(part.center)
	var foot := Vector3(support.foot[0], support.foot[1], support.foot[2])
	var bearing := Vector3(support.bearing[0], support.bearing[1], support.bearing[2])
	if bearing.y <= foot.y or bearing.y - foot.y > 9.0:
		return ""
	# The mesh is cosmetic. Round only the local template key; each instance
	# still uses its exact confirmed center and retains its own pick target.
	var local_foot := foot - center
	var local_bearing := bearing - center
	var components: Array = [part.axis]
	for value in [local_foot.x, local_foot.y, local_foot.z,
			local_bearing.x, local_bearing.y, local_bearing.z]:
		components.append(snappedf(value, 0.0001))
	return JSON.stringify(components)

func _support_mesh(part: Dictionary, id: String, key: String) -> ArrayMesh:
	if _support_meshes.has(key):
		return _support_meshes[key]
	var frame := _confirmed_support(id, part)
	if frame == null:
		return null
	var localize := Transform3D(Basis.IDENTITY, -world_center(part.center))
	var materials: Array[Material] = []
	var surfaces: Array[SurfaceTool] = []
	for child: MeshInstance3D in frame.get_children():
		var finish := child.material_override
		var group := materials.find(finish)
		if group < 0:
			group = materials.size()
			materials.append(finish)
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			surfaces.append(surface)
		Assets.append_triangles(surfaces[group], child.mesh, 0, localize * child.transform)
	var mesh := ArrayMesh.new()
	for index in surfaces.size():
		surfaces[index].commit(mesh)
		mesh.surface_set_material(index, materials[index])
	remove_child(frame)
	frame.free()
	_support_meshes[key] = mesh
	return mesh

func _support_box(parent: Node3D, name_value: String, at: Vector3, size: Vector3,
		material: Material, formed := false) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = name_value
	var shape: Mesh = Visuals.box_mesh(size) if formed else BoxMesh.new()
	if shape is BoxMesh:
		(shape as BoxMesh).size = size
	mesh.mesh = shape
	mesh.position = at
	mesh.material_override = material
	parent.add_child(mesh)

func _cast_mount_foot(parent: Node3D, name_value: String, at: Vector3,
		size: Vector3, casting: Material, fastener_finish: Material) -> void:
	# The broad lower flange and inset upper shoulders form one fixed casting
	# inside its confirmed part box. The native occupied box stays authoritative.
	var half_x := size.x * 0.5
	var half_y := size.y * 0.5
	var shoulder := minf(0.014, size.y * 0.25)
	var inset := minf(0.035, size.x * 0.09)
	var outline := PackedVector2Array([
		Vector2(-half_x, -half_y), Vector2(half_x, -half_y),
		Vector2(half_x, -half_y + shoulder), Vector2(half_x - inset, half_y),
		Vector2(-half_x + inset, half_y), Vector2(-half_x, -half_y + shoulder)])
	var foot := MeshInstance3D.new()
	foot.name = name_value
	foot.mesh = Visuals.prism_mesh(outline, size.z, minf(0.004, size.y * 0.08))
	foot.position = at
	foot.material_override = casting
	parent.add_child(foot)
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			var corner := ("Left" if x < 0.0 else "Right") + ("Near" if z < 0.0 else "Far")
			var fastener := _support_cylinder(parent, name_value + "Fastener" + corner, 0.011,
				0.008, fastener_finish)
			(fastener.mesh as CylinderMesh).radial_segments = 8
			fastener.position = at + Vector3(x * (half_x - inset - 0.022),
				half_y + 0.004, z * (size.z * 0.5 - 0.035))

func _support_cylinder(parent: Node3D, name_value: String, radius: float, height: float,
		material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = name_value
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 20
	mesh.mesh = shape
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh

func _support_beam(parent: Node3D, name_value: String, a: Vector3, b: Vector3,
		width: float, material: Material, formed := false) -> void:
	var direction := b - a
	if direction.length_squared() < 0.000001:
		return
	var mesh := MeshInstance3D.new()
	mesh.name = name_value
	var dimensions := Vector3(width, direction.length(), width)
	var shape: Mesh = Visuals.box_mesh(dimensions) if formed else BoxMesh.new()
	if shape is BoxMesh:
		(shape as BoxMesh).size = dimensions
	mesh.mesh = shape
	var along := direction.normalized()
	var reference := Vector3.RIGHT if absf(along.dot(Vector3.RIGHT)) < 0.95 else Vector3.BACK
	var across := reference.cross(along).normalized()
	mesh.basis = Basis(across, along, across.cross(along))
	mesh.position = (a + b) * 0.5
	mesh.material_override = material
	parent.add_child(mesh)

static func _blade_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		outward: Vector3) -> void:
	var corners: Array[Vector3] = [a, b, c, d]
	# Godot's front face is clockwise when viewed from outside.
	if (b - a).cross(c - a).dot(outward) > 0.0:
		corners = [a, d, c, b]
	for index in [0, 1, 2, 0, 2, 3]:
		var point: Vector3 = corners[index]
		surface.set_normal(outward)
		if absf(outward.y) > 0.5:
			surface.set_uv(Vector2(point.x, point.z) * 4.0)
		elif absf(outward.x) > 0.5:
			surface.set_uv(Vector2(point.z, point.y) * 4.0)
		else:
			surface.set_uv(Vector2(point.x, point.y) * 4.0)
		surface.add_vertex(point)

static func _formed_cutting_blade(north_south := false) -> ArrayMesh:
	if _cutting_blade_meshes.has(north_south):
		return _cutting_blade_meshes[north_south]
	# The fixed native edge box is narrower along Z. Form a shorter front lip
	# for a north/south workcell while preserving the clamped root dimensions.
	var front := -0.175 if north_south else -0.195
	var front_low_left := Vector3(front, -0.025, -0.145)
	var front_low_right := Vector3(front, -0.025, 0.145)
	var front_high_left := Vector3(front, 0.005, -0.145)
	var front_high_right := Vector3(front, 0.005, 0.145)
	var root_low_left := Vector3(0.075, -0.025, -0.145)
	var root_low_right := Vector3(0.075, -0.025, 0.145)
	var root_high_left := Vector3(0.075, 0.080, -0.145)
	var root_high_right := Vector3(0.075, 0.080, 0.145)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_blade_quad(surface, front_high_left, front_high_right, root_high_right, root_high_left,
		Vector3(-0.075 / (0.075 - front), 1.0, 0.0).normalized())
	_blade_quad(surface, front_low_left, front_low_right, root_low_right, root_low_left, Vector3.DOWN)
	_blade_quad(surface, front_low_left, front_low_right, front_high_right, front_high_left, Vector3.LEFT)
	_blade_quad(surface, root_low_left, root_low_right, root_high_right, root_high_left, Vector3.RIGHT)
	_blade_quad(surface, front_low_left, root_low_left, root_high_left, front_high_left, Vector3.FORWARD)
	_blade_quad(surface, front_low_right, root_low_right, root_high_right, front_high_right, Vector3.BACK)
	surface.generate_tangents()
	_cutting_blade_meshes[north_south] = surface.commit()
	return _cutting_blade_meshes[north_south]

static func _formed_receiver_pan() -> ArrayMesh:
	if _receiver_pan_mesh != null:
		return _receiver_pan_mesh
	# The flat seat is the existing native loose-blank height. The raised sheet
	# folds are visual and stay inside the receiver's published occupied box.
	var floor_bottom := 0.0075
	var floor_top := 0.0425
	var rim_top := 0.13
	var floor := SurfaceTool.new()
	floor.begin(Mesh.PRIMITIVE_TRIANGLES)
	_blade_quad(floor, Vector3(-0.17, floor_top, -0.19), Vector3(0.17, floor_top, -0.19),
		Vector3(0.17, floor_top, 0.19), Vector3(-0.17, floor_top, 0.19), Vector3.UP)
	_blade_quad(floor, Vector3(-0.17, floor_bottom, -0.19), Vector3(0.17, floor_bottom, -0.19),
		Vector3(0.17, floor_bottom, 0.19), Vector3(-0.17, floor_bottom, 0.19), Vector3.DOWN)
	floor.generate_tangents()
	_receiver_pan_mesh = floor.commit()
	_receiver_pan_mesh.surface_set_material(0, Finish.material("cast", Color("354442"), 0.72, 0.52))
	var folds := SurfaceTool.new()
	folds.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sign_x in [-1.0, 1.0]:
		var normal_x := Vector3(sign_x, 0, 0)
		_blade_quad(folds, Vector3(sign_x * 0.15, floor_top, -0.19),
			Vector3(sign_x * 0.15, floor_top, 0.19),
			Vector3(sign_x * 0.16, rim_top, 0.19),
			Vector3(sign_x * 0.16, rim_top, -0.19), -normal_x)
		_blade_quad(folds, Vector3(sign_x * 0.17, floor_bottom, -0.19),
			Vector3(sign_x * 0.17, floor_bottom, 0.19),
			Vector3(sign_x * 0.17, rim_top, 0.19),
			Vector3(sign_x * 0.17, rim_top, -0.19), normal_x)
		_blade_quad(folds, Vector3(sign_x * 0.16, rim_top, -0.19),
			Vector3(sign_x * 0.16, rim_top, 0.19),
			Vector3(sign_x * 0.17, rim_top, 0.19),
			Vector3(sign_x * 0.17, rim_top, -0.19), Vector3.UP)
	for sign_z in [-1.0, 1.0]:
		var normal_z := Vector3(0, 0, sign_z)
		_blade_quad(folds, Vector3(-0.17, floor_top, sign_z * 0.17),
			Vector3(0.17, floor_top, sign_z * 0.17),
			Vector3(0.17, rim_top, sign_z * 0.18),
			Vector3(-0.17, rim_top, sign_z * 0.18), -normal_z)
		_blade_quad(folds, Vector3(-0.17, floor_bottom, sign_z * 0.19),
			Vector3(0.17, floor_bottom, sign_z * 0.19),
			Vector3(0.17, rim_top, sign_z * 0.19),
			Vector3(-0.17, rim_top, sign_z * 0.19), normal_z)
		_blade_quad(folds, Vector3(-0.17, rim_top, sign_z * 0.18),
			Vector3(0.17, rim_top, sign_z * 0.18),
			Vector3(0.17, rim_top, sign_z * 0.19),
			Vector3(-0.17, rim_top, sign_z * 0.19), Vector3.UP)
	folds.generate_tangents()
	folds.commit(_receiver_pan_mesh)
	_receiver_pan_mesh.surface_set_material(1, Finish.material("worked", Color("9aaba5"), 0.78, 0.36))
	return _receiver_pan_mesh

func _finish(mesh: MeshInstance3D, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.65
	material.roughness = 0.4
	mesh.material_override = material

func _cylinder(parent: Node3D, name_value: String, radius: float, height: float,
		color: Color, sourced_finish: Material = null) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = name_value
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 24
	mesh.mesh = shape
	if sourced_finish == null:
		_finish(mesh, color)
	else:
		mesh.material_override = sourced_finish
	parent.add_child(mesh)
	return mesh

func _segment(parent: Node3D, a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var direction := b - a
	if direction.length_squared() < 0.000001:
		return
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = Vector3(width, direction.length(), width)
	mesh.mesh = shape
	var along := direction.normalized()
	var reference := Vector3.RIGHT if absf(along.dot(Vector3.RIGHT)) < 0.95 else Vector3.BACK
	var across := reference.cross(along).normalized()
	mesh.basis = Basis(across, along, across.cross(along))
	mesh.position = (a + b) / 2.0
	_finish(mesh, color)
	parent.add_child(mesh)

func _direction(parent: Node3D, radius: float, sign_value: int) -> void:
	var arrow := Node3D.new()
	arrow.name = "ConfirmedDirection"
	arrow.set_meta("sign", sign_value)
	parent.add_child(arrow)
	var end := Vector3.ZERO
	var previous := Vector3.ZERO
	for step in range(6):
		# Positive rate follows the right-hand rule about the local +Y axis.
		var angle := -float(sign_value * step) * PI / 8.0
		var point := Vector3(cos(angle) * radius, 0.13, sin(angle) * radius)
		if step > 0:
			_segment(arrow, previous, point, 0.025, Color("f4df94"))
		previous = point
		end = point
	var tangent := Vector3(end.z, 0, -end.x).normalized() * float(sign_value)
	var radial := Vector3(end.x, 0, end.z).normalized()
	_segment(arrow, end - tangent * 0.13 + radial * 0.07, end, 0.035, Color("f4df94"))
	_segment(arrow, end - tangent * 0.13 - radial * 0.07, end, 0.035, Color("f4df94"))

func _direction_mesh(radius: float, sign_value: int) -> ArrayMesh:
	var key := [radius, sign_value]
	if _direction_meshes.has(key):
		return _direction_meshes[key]
	var holder := Node3D.new()
	_direction(holder, radius, sign_value)
	var arrow: Node3D = holder.get_child(0)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var material: Material
	for segment: MeshInstance3D in arrow.get_children():
		if material == null:
			material = segment.material_override
		Assets.append_triangles(surface, segment.mesh, 0, segment.transform)
	var result := surface.commit()
	result.surface_set_material(0, material)
	holder.free()
	_direction_meshes[key] = result
	return result

func _add_batch(mesh: Mesh, poses: Array[Transform3D], name_value: String) -> MultiMesh:
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = mesh
	batch.instance_count = poses.size()
	var bounds: AABB = poses[0] * mesh.get_aabb()
	for index in poses.size():
		batch.set_instance_transform(index, poses[index])
		bounds = bounds.merge(poses[index] * mesh.get_aabb())
	batch.custom_aabb = bounds
	var visual := MultiMeshInstance3D.new()
	visual.name = name_value
	visual.multimesh = batch
	add_child(visual)
	return batch

func _pick(parent: Node3D, id: String, radius: float, height: float, axle_length: float = 0.0) -> void:
	var body := StaticBody3D.new()
	body.name = "Pick"
	body.collision_layer = Geometry.PICK_LAYER
	body.collision_mask = 0
	body.set_meta("entity", id)
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collider.shape = shape
	body.add_child(collider)
	if axle_length > 0.0:
		var axle_collider := CollisionShape3D.new()
		var axle_shape := CylinderShape3D.new()
		axle_shape.radius = 0.08
		axle_shape.height = axle_length
		axle_collider.shape = axle_shape
		body.add_child(axle_collider)
	parent.add_child(body)

func _relay_case(anchor: Node3D, id: String, part: Dictionary) -> void:
	anchor.set_meta("relay_static", true)
	var case := MeshInstance3D.new()
	case.name = "FixedCase"
	case.mesh = relay_shell_mesh(part.kind, part.axis, int(part.get("relay_axis", 0)))
	anchor.add_child(case)
	var pick := StaticBody3D.new()
	pick.name = "Pick"
	pick.collision_layer = Geometry.PICK_LAYER
	pick.collision_mask = 0
	pick.set_meta("entity", id)
	var collider := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = Vector3.ONE * Geometry.PITCH
	collider.shape = hull
	pick.add_child(collider)
	anchor.add_child(pick)
	var ports: Array = [part.axis] if part.kind == "chain_drive" else [0, 1, 2]
	for axis: int in ports:
		if part.kind != "chain_drive" and axis == part.axis:
			continue
		for side in [-1, 1]:
			var port := Node3D.new()
			port.name = "ShaftPort%d%d" % [axis, side]
			port.set_meta("relay_port_axis", axis)
			var first := 0 if part.axis != 0 else 1
			var factor: int = 1 if part.kind == "chain_drive" else (1 if axis == first else -1) * side
			port.set_meta("relay_factor", factor)
			port.position[axis] = float(side) * 0.72
			port.basis = axis_basis(axis)
			anchor.add_child(port)
			_cylinder(port, "BearingSocket", 0.245, 0.045, Color("303c3e"),
				Finish.material("cast", Color("303c3e"), 0.75, 0.52))
			_cylinder(port, "MachinedCollar", 0.205, 0.07, Color("b8c1b8"),
				Finish.material("worked", Color("b8c1b8"), 0.85, 0.34))
			_cylinder(port, "ExposedSpindle", 0.11, 0.12, Color("667b7a"),
				Finish.material("worked", Color("667b7a"), 0.84, 0.4))
			_segment(port, Vector3(-0.11, 0.055, 0), Vector3(0.11, 0.055, 0), 0.024, Color("e7c780"))
	if part.kind == "chain_drive":
		for side in [-1, 1]:
			var marker := MeshInstance3D.new()
			marker.name = "ChainLinkDirection"
			var stripe := BoxMesh.new()
			stripe.size = Vector3(0.04, 0.04, 0.04)
			stripe.size[part.axis] = 0.34
			marker.mesh = stripe
			marker.position[part.relay_axis] = float(side) * (Geometry.PITCH / 2.0 - 0.045)
			_finish(marker, Color("d3a761"))
			anchor.add_child(marker)

static func relay_shell_mesh(kind: String, closed_axis: int, link_axis: int) -> ArrayMesh:
	var key := "%s:%d:%d" % [kind, closed_axis, link_axis]
	if _relay_shells.has(key):
		return _relay_shells[key]
	var body := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outline := PackedVector2Array([Vector2(-0.62, -0.69), Vector2(0.62, -0.69),
		Vector2(0.70, -0.61), Vector2(0.70, 0.61), Vector2(0.62, 0.69),
		Vector2(-0.62, 0.69), Vector2(-0.70, 0.61), Vector2(-0.70, -0.61)])
	Assets.append_triangles(body, Visuals.prism_mesh(outline, 1.40, 0.008), 0, Transform3D.IDENTITY)
	var shell := ArrayMesh.new()
	body.commit(shell)
	shell.surface_set_material(0, Finish.material("cast",
		Color("536369") if kind == "chain_drive" else Color("68736e"), 0.78, 0.50))
	var panels := SurfaceTool.new()
	panels.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cover_size := Vector3.ONE * 1.16
	cover_size[closed_axis] = 0.055
	var cover := BoxMesh.new()
	cover.size = cover_size
	for side in [-1.0, 1.0]:
		var at := Vector3.ZERO
		at[closed_axis] = side * 0.705
		Assets.append_triangles(panels, cover, 0, Transform3D(Basis.IDENTITY, at))
	if kind == "chain_drive":
		var hatch := BoxMesh.new()
		hatch.size = Vector3.ONE * 0.92
		hatch.size[link_axis] = 0.045
		for side in [-1.0, 1.0]:
			var at := Vector3.ZERO
			at[link_axis] = side * 0.72
			Assets.append_triangles(panels, hatch, 0, Transform3D(Basis.IDENTITY, at))
	panels.commit(shell)
	shell.surface_set_material(1, Finish.material("cast", Color("35464b"), 0.72, 0.60))
	var trim := SurfaceTool.new()
	trim.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Two raised ribs distinguish a guarded mechanical case from a plain cube.
	# A chain case also carries one continuous external cover along its confirmed
	# link axis; neither shape describes motion or adds a construction port.
	var rib := BoxMesh.new()
	rib.size = Vector3(1.39, 0.045, 0.075)
	for side in [-1.0, 1.0]:
		Assets.append_triangles(trim, rib, 0, Transform3D(Basis.IDENTITY,
			Vector3(0, 0.745, side * 0.43)))
	var upright := BoxMesh.new()
	upright.size = Vector3(0.075, 1.28, 0.075)
	for x in [-0.62, 0.62]:
		for z in [-0.62, 0.62]:
			Assets.append_triangles(trim, upright, 0,
				Transform3D(Basis.IDENTITY, Vector3(x, 0, z)))
	var fastener := CylinderMesh.new()
	fastener.top_radius = 0.035
	fastener.bottom_radius = 0.035
	fastener.height = 0.024
	fastener.radial_segments = 8
	var first_side := (closed_axis + 1) % 3
	var second_side := (closed_axis + 2) % 3
	var bolt_normal := Vector3.UP
	if closed_axis == 0:
		bolt_normal = Vector3.RIGHT
	elif closed_axis == 2:
		bolt_normal = Vector3.BACK
	var fastener_basis := Basis(Quaternion(Vector3.UP, bolt_normal))
	for face in [-1.0, 1.0]:
		for first in [-0.47, 0.47]:
			for second in [-0.47, 0.47]:
				var bolt_at := Vector3.ZERO
				bolt_at[closed_axis] = face * 0.744
				bolt_at[first_side] = first
				bolt_at[second_side] = second
				Assets.append_triangles(trim, fastener, 0, Transform3D(fastener_basis, bolt_at))
	if kind == "chain_drive":
		var spine := BoxMesh.new()
		spine.size = Vector3(0.27, 0.08, 0.27)
		spine.size[link_axis] = 1.48
		var spine_at := Vector3(0, 0.745, 0)
		if link_axis == 1:
			spine.size.x = 0.08
			spine_at = Vector3(0.745, 0, 0)
		Assets.append_triangles(trim, spine, 0, Transform3D(Basis.IDENTITY, spine_at))
		var hatch_bar := BoxMesh.new()
		hatch_bar.size = Vector3(0.56, 0.065, 0.035)
		var bar_axis := (link_axis + 1) % 3
		hatch_bar.size[link_axis] = 0.035
		hatch_bar.size[bar_axis] = 0.56
		for face in [-1.0, 1.0]:
			for row in [-0.22, 0.0, 0.22]:
				var bar_at := Vector3.ZERO
				bar_at[link_axis] = face * 0.76
				bar_at[(link_axis + 2) % 3] = row
				Assets.append_triangles(trim, hatch_bar, 0, Transform3D(Basis.IDENTITY, bar_at))
	trim.commit(shell)
	shell.surface_set_material(2, Finish.material("worked", Color("a3ada6"), 0.82, 0.39))
	_relay_shells[key] = shell
	return shell

func _belt_span(id: String, span: Variant, parts: Dictionary, rendered: Dictionary) -> void:
	if not span is Dictionary or typeof(span.get("from")) != TYPE_STRING or typeof(span.get("to")) != TYPE_STRING:
		return
	var first: Variant = parts.get(span.from)
	var last: Variant = parts.get(span.to)
	if not _valid_part(first) or not _valid_part(last) or first.kind != "shaft" or last.kind != "shaft" or first.axis != last.axis or first.half_span != 2 or last.half_span != 2:
		return
	var first_point := Vector3i(first.center[0], first.center[1], first.center[2])
	var last_point := Vector3i(last.center[0], last.center[1], last.center[2])
	var delta := last_point - first_point
	var steps: int = maxi(absi(delta.x), maxi(absi(delta.y), absi(delta.z))) / 4
	if steps < 1 or steps > 19 or delta[first.axis] != 0:
		return
	var step := Vector3i.ZERO
	var changed := 0
	for axis in 3:
		if first_point[axis] % 4 != 0 or last_point[axis] % 4 != 0:
			return
		if delta[axis] != 0:
			if absi(delta[axis]) != steps * 4:
				return
			changed += 1
			step[axis] = 4 if delta[axis] > 0 else -4
	if changed > 2 or (first.axis == 1 and changed != 1):
		return
	var distance: float = Vector3(delta).length() * UNIT
	var tangent := Vector3(delta).normalized()
	if delta.x < 0 or (delta.x == 0 and delta.y < 0) or (delta.x == 0 and delta.y == 0 and delta.z < 0):
		tangent = -tangent
	var spindle := Vector3.ZERO
	spindle[first.axis] = 1.0
	var normal := spindle.cross(tangent).normalized()
	if normal.y < -0.001:
		spindle = -spindle
		normal = -normal
	var loop_basis := Basis(tangent, normal, spindle)
	var anchor := Node3D.new()
	anchor.name = "ConfirmedBelt"
	anchor.set_meta("entity", id)
	anchor.set_meta("kind", "belt_span")
	anchor.position = (world_center(first.center) + world_center(last.center)) / 2.0
	anchor.set_meta("cargo_start", world_center(first.center) - anchor.position)
	anchor.set_meta("cargo_end", world_center(last.center) - anchor.position)
	anchor.set_meta("cargo_slots", steps + 1)
	anchor.set_meta("cargo_allowed", first.axis != 1 and (delta.x != 0 or delta.z != 0))
	var travel_axis := 2 if first.axis == 0 else 0
	var positive_world: bool = first.axis == 0
	anchor.set_meta("cargo_positive_rate_direction",
		1 if positive_world == (last.center[travel_axis] > first.center[travel_axis]) else -1)
	anchor.set_meta("cargo_subticks_per_tick", INCLINED_SUBTICKS_PER_TICK if delta.y != 0 else BELT_SUBTICKS_PER_TILE)
	add_child(anchor)
	_cargo_anchors.append(anchor)
	var loop := Assets.belt_loop(anchor, distance, 0)
	if loop != null:
		loop.basis = loop_basis
		# The source material is cached across spans. A private material keeps
		# differently driven loops from overwriting each other's UV phase.
		loop.material_override = loop.material_override.duplicate()
		var finish := loop.material_override as StandardMaterial3D
		var length := 2.0 * distance + TAU * Assets.SPAN_OUTER_RADIUS
		var repeats := maxi(1, roundi(length / Assets.ConveyorArt.SOURCE_METRES))
		anchor.set_meta("belt_shaft", span.from)
		anchor.set_meta("belt_uv_origin", finish.uv1_offset.x)
		# The top run's increasing U follows tangent. A positive axle rotation
		# moves that run in the opposite direction to the spindle cross normal.
		anchor.set_meta("belt_uv_factor", spindle[first.axis] * Assets.SPAN_OUTER_RADIUS * repeats / length)
	var pulley_offsets: Array[float] = []
	for part_id: Variant in parts:
		var pulley: Variant = parts[part_id]
		if not rendered.has(part_id) or not _valid_part(pulley) or pulley.kind != "shaft" or pulley.axis != first.axis:
			continue
		var point := Vector3i(pulley.center[0], pulley.center[1], pulley.center[2])
		for index in range(steps + 1):
			if point == first_point + step * index:
				Assets.belt_pulley(rendered[part_id])
				if index > 0 and index < steps:
					pulley_offsets.append((world_center(pulley.center) - anchor.position).dot(loop_basis.x))
				break
	# Keep the pick body between the pulleys so each endpoint shaft remains
	# independently selectable. This body is for picking, not actor collision.
	var body := StaticBody3D.new()
	body.name = "Pick"
	body.collision_layer = Geometry.PICK_LAYER
	body.collision_mask = 0
	body.set_meta("entity", id)
	body.basis = loop_basis
	# Leave a small gap around each intermediate pulley so a ray aimed at its
	# shaft does not hit the belt's selection body first. The endpoint margins
	# keep the original independent endpoint selection behavior.
	pulley_offsets.sort()
	var cursor := -distance / 2.0 + Geometry.PITCH * 0.35
	var end := distance / 2.0 - Geometry.PITCH * 0.35
	for offset in pulley_offsets:
		var gap_start := clampf(offset - 0.18, cursor, end)
		_add_belt_pick_section(body, cursor, gap_start)
		cursor = clampf(offset + 0.18, cursor, end)
	_add_belt_pick_section(body, cursor, end)
	anchor.add_child(body)

func _refresh_belt_cargo(spans: Variant) -> void:
	if not spans is Dictionary:
		return
	for anchor: Node3D in _cargo_anchors:
		var id: String = anchor.get_meta("entity", "")
		var span: Variant = spans.get(id)
		if not span is Dictionary:
			continue
		var slots: Variant = span.get("slots", [])
		var cargo_key := JSON.stringify([slots, span.get("phase")])
		if _cargo_keys.get(id) == cargo_key:
			continue
		_cargo_keys[id] = cargo_key
		_cargo_elapsed[id] = 0.0
		var existing := {}
		for child: Node in anchor.get_children():
			if child.has_meta("belt_slot"):
				existing[int(child.get_meta("belt_slot"))] = child
		if not anchor.get_meta("cargo_allowed", false) or not slots is Array or slots.size() != int(anchor.get_meta("cargo_slots")):
			for child: Node in existing.values():
				anchor.remove_child(child)
				child.free()
			continue
		var first_position: Vector3 = anchor.get_meta("cargo_start")
		var last_position: Vector3 = anchor.get_meta("cargo_end")
		for index in range(slots.size()):
			var item: Variant = slots[index]
			if not item is Dictionary or typeof(item.get("raw")) != TYPE_INT or typeof(item.get("products")) != TYPE_INT or not item.get("work_lots") is Array:
				continue
			var raw: bool = item.raw == 1 and item.products == 0 and item.work_lots.is_empty()
			var product: bool = item.raw == 0 and item.products == 1 and item.work_lots.is_empty()
			var work: bool = item.raw == 0 and item.products == 0 and item.work_lots.size() == 1
			if not raw and not product and not work:
				continue
			var fraction := belt_slot_fraction(slots, index, span.get("phase"))
			var position := first_position.lerp(last_position, (float(index) + fraction) / float(slots.size() - 1))
			position.y += 0.18 if product else 0.24
			var kind := "product" if product else ("work" if work else "raw")
			var visual: Node3D = existing.get(index)
			if visual != null and visual.get_meta("belt_item") != kind:
				anchor.remove_child(visual)
				visual.free()
				visual = null
			if visual == null:
				visual = Items.stamped_plate(anchor, position) if product else Items.workpiece_billet(anchor, position)
			else:
				visual.position = position
			visual.set_meta("belt_slot", index)
			visual.set_meta("belt_item", kind)
			existing.erase(index)
		for child: Node in existing.values():
			anchor.remove_child(child)
			child.free()

func _advance_belt_cargo(delta: float, snapshot: Dictionary) -> void:
	var spans: Variant = snapshot.get("belt_spans", {})
	if not spans is Dictionary:
		return
	for anchor: Node3D in _cargo_anchors:
		if not anchor.get_meta("cargo_allowed", false):
			continue
		var id: String = anchor.get_meta("entity", "")
		var span: Variant = spans.get(id)
		if not span is Dictionary or not span.get("slots") is Array or typeof(span.get("phase")) != TYPE_INT:
			continue
		var slots: Array = span.slots
		if slots.size() != int(anchor.get_meta("cargo_slots")) or absi(span.phase) >= int(BELT_SUBTICKS_PER_TILE):
			continue
		var source: String = str(anchor.get_meta("belt_shaft", ""))
		var rate := signed_rate(snapshot.motion.get(source))
		var elapsed := minf(float(_cargo_elapsed.get(id, 0.0)) + delta, CARGO_TICK_SECONDS)
		_cargo_elapsed[id] = elapsed
		# The fitted loop already uses this confirmed source rate. Display cargo
		# through its current tick, never beyond one tile or a blocked end.
		var direction := float(anchor.get_meta("cargo_positive_rate_direction"))
		var phase := clampf(float(span.phase) + rate * direction *
			float(anchor.get_meta("cargo_subticks_per_tick")) * elapsed / CARGO_TICK_SECONDS,
			-BELT_SUBTICKS_PER_TILE, BELT_SUBTICKS_PER_TILE)
		var first_position: Vector3 = anchor.get_meta("cargo_start")
		var last_position: Vector3 = anchor.get_meta("cargo_end")
		for item: Node in anchor.get_children():
			if not item is Node3D or not item.has_meta("belt_slot"):
				continue
			var index := int(item.get_meta("belt_slot"))
			var fraction := belt_visual_fraction(slots, index, phase)
			var position := first_position.lerp(last_position, (float(index) + fraction) / float(slots.size() - 1))
			position.y += 0.18 if item.get_meta("belt_item") == "product" else 0.24
			item.position = position

func _add_belt_pick_section(body: StaticBody3D, start: float, end: float) -> void:
	if end - start <= 0.001:
		return
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(end - start, 0.3, Geometry.PITCH * 0.55)
	collider.position.x = (start + end) / 2.0
	collider.shape = box
	body.add_child(collider)

static func belt_slot_fraction(slots: Array, index: int, phase: Variant) -> float:
	# The shared phase advances a whole chain together. If the chain reaches a
	# blocked end, do not invent partial movement through another item or beyond
	# the confirmed span. No wall clock or new item identity is introduced.
	if typeof(phase) != TYPE_INT or phase <= -4096 or phase >= 4096 or phase == 0 or index < 0 or index >= slots.size():
		return 0.0
	var direction := 1 if phase > 0 else -1
	var next := index + direction
	while next >= 0 and next < slots.size():
		if slots[next] == null:
			return float(phase) / BELT_SUBTICKS_PER_TILE
		next += direction
	return 0.0

static func belt_visual_fraction(slots: Array, index: int, phase: float) -> float:
	if not is_finite(phase) or is_zero_approx(phase) or index < 0 or index >= slots.size():
		return 0.0
	var direction := 1 if phase > 0.0 else -1
	var next := index + direction
	while next >= 0 and next < slots.size():
		if slots[next] == null:
			return clampf(phase / BELT_SUBTICKS_PER_TILE, -1.0, 1.0)
		next += direction
	return 0.0

func _shaft_coupling(shaft: Dictionary, gear: Dictionary, parent: Node3D,
		shaft_id: String, gear_id: String) -> void:
	if shaft.axis != gear.axis:
		return
	var offset: float = (gear.center[shaft.axis] - shaft.center[shaft.axis]) * UNIT
	# Fit outside the existing hub and fasteners, towards shaft interior. A
	# short admitted shaft may have no room for this art; never extend it.
	var center: float = offset + (-1.0 if offset > 0.0 else 1.0) * 0.146
	if absf(center) + Assets.COUPLING_HALF_LENGTH > float(shaft.half_span) * UNIT:
		return
	var fitting := Node3D.new()
	fitting.name = "ConfirmedCoupling%d" % parent.get_child_count()
	fitting.position.y = center
	fitting.set_meta("shaft_coupling", true)
	fitting.set_meta("shaft", shaft_id)
	fitting.set_meta("gear", gear_id)
	if Assets.coupling(fitting):
		# Both halves share the existing shaft's cosmetic phase. No second
		# animation clock, constraint, native contact or pick body is created.
		parent.add_child(fitting)
	else:
		fitting.free()

func _shaft_splice(first: Dictionary, second: Dictionary, parent: Node3D,
		first_id: String, second_id: String) -> void:
	if first.axis != second.axis:
		return
	var axis: int = first.axis
	if second.center[axis] == first.center[axis]:
		return
	var direction := 1 if second.center[axis] > first.center[axis] else -1
	for coordinate in range(3):
		if coordinate != axis and first.center[coordinate] != second.center[coordinate]:
			return
	# A confirmed graph edge is required, but only an exact butt seam can carry
	# this rigid fitting. Never bridge a gap or cover an overlapping shaft.
	var seam: int = first.center[axis] + direction * first.half_span
	if seam != second.center[axis] - direction * second.half_span \
			or Assets.COUPLING_HALF_LENGTH > minf(first.half_span, second.half_span) * UNIT:
		return
	var fitting := Node3D.new()
	fitting.name = "ConfirmedShaftSplice%d" % parent.get_child_count()
	fitting.position.y = float(direction * first.half_span) * UNIT
	fitting.set_meta("shaft_splice", true)
	fitting.set_meta("first_shaft", first_id)
	fitting.set_meta("second_shaft", second_id)
	if Assets.coupling(fitting):
		# The sourced halves rotate with their first confirmed shaft. This is
		# presentation only; the native engagement owns connectivity and rate.
		parent.add_child(fitting)
	else:
		fitting.free()

func _placed_component(anchor: Node3D, kind: String, drive_direction: Vector3,
		occupied_size: Vector3, press_role: String, collector_angle: float,
		collector_support_drop: float) -> void:
	var timber: Material = WheelArt.support_timber_finish()
	if timber == null:
		timber = Visuals.material(Color("76604a"), 0.12, 0.78)
	var worked := Finish.material("worked", Color("9aaba5"), 0.78, 0.36)
	var dark := Finish.material("cast", Color("354442"), 0.72, 0.52)
	match kind:
		"wooden_frame":
			for x in [-0.155, 0.155]:
				for z in [-0.155, 0.155]:
					_support_box(anchor, "GroundedPost", Vector3(x, -0.05, z), Vector3(0.055, 0.80, 0.055), timber, true)
					_support_box(anchor, "PostShoe", Vector3(x, -0.415, z), Vector3(0.09, 0.045, 0.09), dark, true)
			for z in [-0.155, 0.155]:
				_support_beam(anchor, "SideBrace", Vector3(-0.14, -0.29, z),
					Vector3(0.14, 0.22, z), 0.035, timber, true)
			_support_box(anchor, "OpenWorkBed", Vector3(0, 0.35, 0), Vector3(0.405, 0.06, 0.405), timber, true)
			for z in [-0.155, 0.155]:
				_support_box(anchor, "BedIron", Vector3(0, 0.385, z), Vector3(0.35, 0.012, 0.025), worked, true)
			for x in [-0.155, 0.155]:
				for z in [-0.155, 0.155]:
					var peg := _support_cylinder(anchor, "JoineryPeg%d" % anchor.get_child_count(), 0.011, 0.018, timber)
					peg.position = Vector3(x, 0.384, z)
		"tool_mount":
			if press_role == "mount":
				# This crown is a separate fitted part. Its sockets reach the guide
				# face without inventing another pick body or covering the work face.
				for x in [-0.145, 0.145]:
					_support_box(anchor, "PressCrownSocket", Vector3(x, -0.035, 0),
						Vector3(0.045, 0.27, 0.30), dark)
				_support_box(anchor, "PressCrown", Vector3(0, 0.115, 0),
					Vector3(0.37, 0.075, 0.34), worked)
				_support_box(anchor, "PressCrownBearing", Vector3(0, -0.07, 0),
					Vector3(0.20, 0.10, 0.20), worked)
			else:
				if collector_support_drop > 0.0:
					_collector_tool_support(anchor, "Mount", collector_angle,
						collector_support_drop, -0.13, 0.21, dark, worked)
				_cast_mount_foot(anchor, "SlidingFoot", Vector3(0, -0.11, 0),
					Vector3(0.37, 0.06, 0.33), dark, worked)
				var clamp := ClampBody.instantiate() as Node3D
				clamp.name = "CastToolClamp"
				# The selected source frame and fixed jaw are static. Their opening
				# faces the confirmed cutter; the donor dial and handle are absent.
				var jaw_seat := Vector3(-0.015, -0.08, 0)
				# The native box is 2 cm narrower along Z. Seat the rigid source
				# casting 7 mm back when it faces north or south; keep its scale.
				if absf(sin(collector_angle)) > 0.5:
					jaw_seat.x += 0.007
				clamp.position = Basis(Vector3.UP, collector_angle) * jaw_seat
				clamp.rotation.y = PI * 0.5 + collector_angle
				anchor.add_child(clamp)
		"anvil":
			var bottom := -occupied_size.y * 0.5
			_support_box(anchor, "CastPedestalFoot", Vector3(0, bottom + 0.03, 0),
				Vector3(0.265, 0.055, 0.265), dark)
			_support_box(anchor, "CastPedestal", Vector3(0, bottom + 0.14, 0),
				Vector3(0.17, 0.235, 0.17), dark)
			_support_box(anchor, "OpenAnvilSeat", Vector3(0, bottom + 0.29, 0),
				Vector3(0.265, 0.055, 0.245), worked)
			for z in [-0.107, 0.107]:
				_support_box(anchor, "AnvilEdge", Vector3(0, bottom + 0.35, z),
					Vector3(0.23, 0.06, 0.03), dark)
		"ram_face":
			var bottom := -occupied_size.y * 0.5
			_support_box(anchor, "MovingDie", Vector3(0, bottom + 0.045, 0),
				Vector3(0.25, 0.075, 0.25), worked)
			_support_box(anchor, "RamBody", Vector3(0, bottom + occupied_size.y * 0.5, 0),
				Vector3(0.125, occupied_size.y - 0.10, 0.125), dark)
			for z in [-0.105, 0.105]:
				_support_box(anchor, "RamSlide", Vector3(0, bottom + occupied_size.y * 0.57, z),
					Vector3(0.20, occupied_size.y * 0.64, 0.028), worked)
		"sliding_guide":
			for x in [-0.103, 0.103]:
				_support_box(anchor, "GuideRail", Vector3(x, 0, 0),
					Vector3(0.045, occupied_size.y - 0.012, 0.21), worked)
			_support_box(anchor, "GuideCrown", Vector3(0, occupied_size.y * 0.5 - 0.035, 0),
				Vector3(0.25, 0.055, 0.25), dark)
		"wooden_cog", "softmetal_cog":
			var direction := drive_direction.normalized() if drive_direction.length_squared() > 0.5 else Vector3.UP
			var reference := Vector3.RIGHT if absf(direction.dot(Vector3.RIGHT)) < 0.95 else Vector3.BACK
			var across := reference.cross(direction).normalized()
			var rotor := Node3D.new()
			rotor.name = "PlacedDriveCog"
			rotor.basis = Basis(across, direction, across.cross(direction))
			anchor.add_child(rotor)
			var finish: Material = timber if kind == "wooden_cog" else worked
			_support_cylinder(rotor, "CogRim", 0.095, 0.05, finish)
			_support_cylinder(rotor, "CogHub", 0.05, 0.105, dark)
			for index in range(12):
				var angle := TAU * float(index) / 12.0
				_support_box(rotor, "CogTooth%02d" % index, Vector3.ZERO,
					Vector3(0.027, 0.065, 0.035), finish)
				# _support_box installs the mesh but has no return value.
				var placed_tooth := rotor.get_child(rotor.get_child_count() - 1) as MeshInstance3D
				placed_tooth.position = Vector3(sin(angle), 0, cos(angle)) * 0.113
				placed_tooth.rotation.y = angle
		"cutting_edge":
			if collector_support_drop > 0.0:
				_collector_tool_support(anchor, "Edge", collector_angle,
					collector_support_drop, -0.10, 0.2025, dark, worked)
			_cast_mount_foot(anchor, "BladeCarrier", Vector3(0, -0.07, 0),
				Vector3(0.40, 0.07, 0.32), dark, worked)
			var blade := MeshInstance3D.new()
			blade.name = "FormedBlade"
			blade.mesh = _formed_cutting_blade(absf(sin(collector_angle)) > 0.5)
			blade.rotation.y = collector_angle
			blade.material_override = worked
			anchor.add_child(blade)
			var facing := Basis(Vector3.UP, collector_angle)
			_support_box(anchor, "BladeClamp", facing * Vector3(0.095, 0.080, 0),
				Vector3(0.11, 0.025, 0.30), dark)
			(anchor.get_node("BladeClamp") as MeshInstance3D).rotation.y = collector_angle
			for z in [-0.09, 0.09]:
				var fastener := _support_cylinder(anchor, "ClampFastener", 0.017, 0.015, worked)
				fastener.position = facing * Vector3(0.11, 0.095, z)
		"receiver_tray":
			# The existing loose-blank centre is at the grid anchor. Its 8 cm
			# visual sits on a level seat within the folded, open receiver.
			var pan := MeshInstance3D.new()
			pan.name = "OpenPan"
			pan.mesh = _formed_receiver_pan()
			anchor.add_child(pan)
			# The near-side hooks and underside rails give this independently placed
			# receiver a visible mounting direction without bridging the native
			# occupied gap or inventing a second material path.
			for x in [-0.125, 0.125]:
				var side := "Left" if x < 0.0 else "Right"
				_support_box(anchor, "ReceiverHook" + side, Vector3(x, 0.005, -0.1925),
					Vector3(0.045, 0.17, 0.025), dark, true)
				_support_beam(anchor, "ReceiverUnderRail" + side, Vector3(x, -0.08, -0.185),
					Vector3(x, 0.005, 0.105), 0.025, dark, true)
			for x in [-0.161, 0.161]:
				_support_box(anchor, "ReceiverRolledSide%s" % ("Left" if x < 0.0 else "Right"),
					Vector3(x, 0.133, 0),
					Vector3(0.018, 0.014, 0.37), dark, true)
			for z in [-0.18, 0.18]:
				_support_box(anchor, "ReceiverRolledEnd%s" % ("Near" if z < 0.0 else "Far"),
					Vector3(0, 0.133, z),
					Vector3(0.34, 0.014, 0.018), dark, true)
			for x in [-0.13, 0.13]:
				for z in [-0.17, 0.17]:
					var name_value := "ReceiverRivet%s%s" % ["Left" if x < 0.0 else "Right",
						"Near" if z < 0.0 else "Far"]
					var rivet := _support_cylinder(anchor, name_value, 0.009, 0.007, worked)
					rivet.position = Vector3(x, 0.141, z)
		"wooden_shaft", "softmetal_shaft":
			_cast_mount_foot(anchor, "BearingFoot", Vector3(0, -0.07, 0),
				Vector3(0.35, 0.07, 0.35), dark, worked)
			var fitted := drive_direction.length_squared() > 0.5
			var rod := Node3D.new()
			rod.name = "LooseDriveShaft"
			anchor.add_child(rod)
			var direction := drive_direction.normalized() if fitted else Vector3.UP
			var reference := Vector3.RIGHT if absf(direction.dot(Vector3.RIGHT)) < 0.95 else Vector3.BACK
			var across := reference.cross(direction).normalized()
			rod.basis = Basis(across, direction, across.cross(direction))
			rod.position.y = 0.0 if fitted else 0.035
			Assets.shaft(rod, 0.32 if fitted else 0.14, Color("947658") if kind == "wooden_shaft" else Color("9aaba5"))
			var core := rod.get_node("Shaft") as MeshInstance3D
			core.material_override = timber if kind == "wooden_shaft" else worked
			if fitted:
				# The two static journals belong to the confirmed frame-facing axis.
				# Neither their geometry nor this rod becomes a second drive or collider.
				for sign_value in [-1.0, 1.0]:
					var suffix := "Near" if sign_value < 0.0 else "Far"
					var bearing := _support_cylinder(anchor, "BearingShell" + suffix, 0.07, 0.045, dark)
					bearing.position = direction * sign_value * 0.115
					bearing.basis = rod.basis
					_support_box(anchor, "BearingSeat" + suffix, bearing.position + Vector3.DOWN * 0.05,
						Vector3(0.10, 0.06, 0.10), dark)
		_:
			_support_box(anchor, "UnfittedPart", Vector3.ZERO, Vector3(0.24, 0.20, 0.24), dark)

func _collector_tool_support(anchor: Node3D, label: String, angle: float,
		drop: float, top: float, rear_face: float, cast: Material,
		worked: Material) -> void:
	# This visible load path is allowed only when the trusted native occupied
	# volume reaches the frame floor. Each placed part owns its own two posts;
	# removing a neighbour cannot leave a decorative bridge in empty space.
	var facing := Basis(Vector3.UP, angle)
	var height := drop + top
	if height <= 0.0:
		return
	for side in [-1.0, 1.0]:
		var suffix := "Left" if side < 0.0 else "Right"
		_support_box(anchor, label + "SupportPost" + suffix,
			facing * Vector3(0.12, (-drop + top) * 0.5, side * 0.11),
			Vector3(0.045, height, 0.045), cast, true)
		(anchor.get_node(label + "SupportPost" + suffix) as MeshInstance3D).rotation.y = angle
		_support_box(anchor, label + "GroundShoe" + suffix,
			facing * Vector3(0.12, -drop + 0.018, side * 0.11),
			Vector3(0.075, 0.036, 0.075), worked, true)
		(anchor.get_node(label + "GroundShoe" + suffix) as MeshInstance3D).rotation.y = angle
		_support_beam(anchor, label + "KneeBrace" + suffix,
			facing * Vector3(0.12, -drop + 0.14, side * 0.11),
			facing * Vector3(-0.12, top - 0.02, side * 0.11),
			0.025, worked, true)
		if label == "Mount":
			# The two rails carry the independent edge's rear dock without
			# closing the open material path between the cutter and receiver.
			_support_box(anchor, "MountForwardRail" + suffix,
				facing * Vector3(-0.025, -0.24, side * 0.11),
				Vector3(0.37, 0.045, 0.045), worked, true)
			(anchor.get_node("MountForwardRail" + suffix) as MeshInstance3D).rotation.y = angle
	if label == "Mount":
		# The frame's open timber bed ends at the same floor-relative height
		# in both admitted collector layouts. This tie reaches its near face.
		_support_box(anchor, "MountFrameTie",
			facing * Vector3(0.185, 0.835 - drop, 0),
			Vector3(0.05, 0.05, 0.27), worked, true)
		(anchor.get_node("MountFrameTie") as MeshInstance3D).rotation.y = angle
	_support_box(anchor, label + "RearDock", facing * Vector3(rear_face - 0.0225,
		top - 0.025, 0), Vector3(0.045, 0.05, 0.27), worked, true)
	(anchor.get_node(label + "RearDock") as MeshInstance3D).rotation.y = angle

func _render_placed_components(snapshot: Dictionary, boxes: Dictionary) -> void:
	var drives: Dictionary = {}
	var press_roles: Dictionary = {}
	var collector_facings: Dictionary = {}
	var collector_floors: Dictionary = {}
	var by_cell: Dictionary = {}
	var placed: Variant = snapshot.get("placed_components", {})
	if placed is Dictionary:
		for id: String in placed:
			var record: Variant = placed[id]
			if not record is Dictionary or not record.get("center") is Array or record.center.size() != 3:
				continue
			by_cell[Vector3i(record.center[0], record.center[1], record.center[2])] = id
	var assemblies: Variant = snapshot.get("collector_assemblies", [])
	if assemblies is Array:
		for assembly: Variant in assemblies:
			if not assembly is Dictionary:
				continue
			# Native trusted ore faces exist before all five parts are ready.
			# Exact face-relative cells orient only parts already placed there;
			# no visual angle is a new work or connection decision.
			var center: Variant = assembly.get("center")
			var toward: Variant = assembly.get("toward_ore")
			if assembly.get("status") in ["ready", "missing_frame", "missing_mount",
					"missing_edge", "missing_receiver", "missing_shaft"] \
					and center is Array and center.size() == 3 and toward is Array and toward.size() == 3 \
					and typeof(center[0]) == TYPE_INT and typeof(center[1]) == TYPE_INT \
					and typeof(center[2]) == TYPE_INT and typeof(toward[0]) == TYPE_INT \
					and typeof(toward[1]) == TYPE_INT and typeof(toward[2]) == TYPE_INT:
				var direction := Vector3i(toward[0], toward[1], toward[2])
				if direction.y == 0 and absi(direction.x) + absi(direction.z) == 1:
					var origin := Vector3i(center[0], center[1], center[2])
					var angle := atan2(float(direction.z), -float(direction.x))
					for height in [0, 1]:
						var base := origin + Vector3i(0, height, 0)
						for step in [1, 2]:
							var id: Variant = by_cell.get(base + direction * step)
							var expected := "tool_mount" if step == 1 else "cutting_edge"
							if boxes.has(id) and boxes[id].component == expected:
								collector_facings[id] = angle
								collector_floors[id] = float(origin.y) * UNIT
			if assembly.get("status") != "ready" or not assembly.get("parts") is Dictionary:
				continue
			var frame_id: Variant = assembly.parts.get("frame")
			var shaft_id: Variant = assembly.parts.get("shaft")
			if not boxes.has(frame_id) or not boxes.has(shaft_id):
				continue
			var toward_frame: Vector3 = boxes[frame_id].center - boxes[shaft_id].center
			toward_frame.y = 0.0
			if toward_frame.length_squared() > 0.01:
				drives[shaft_id] = toward_frame.normalized()
	var presses: Variant = snapshot.get("press_assemblies", [])
	if presses is Array:
		for press: Variant in presses:
			if not press is Dictionary:
				continue
			# The frame's native cell and the placed cells keep partial fittings
			# styled and oriented when a drive part is removed. Readiness still
			# comes only from the native assembly projection.
			var cell: Variant = press.get("center")
			if cell is Array and cell.size() == 3:
				var origin := Vector3i(cell[0], cell[1], cell[2])
				var mount_id: Variant = by_cell.get(origin + Vector3i(0, 4, 0))
				if boxes.has(mount_id) and boxes[mount_id].component == "tool_mount":
					press_roles[mount_id] = "mount"
				for direction in [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.FORWARD, Vector3i.BACK]:
					var shaft_id: Variant = by_cell.get(origin + Vector3i(0, 4, 0) + direction)
					if not boxes.has(shaft_id) or not boxes[shaft_id].component.ends_with("_shaft"):
						continue
					drives[shaft_id] = Vector3(-direction.x, 0, -direction.z)
					var cog_id: Variant = by_cell.get(origin + Vector3i(0, 4, 0) + direction * 2)
					if boxes.has(cog_id) and boxes[cog_id].component.ends_with("_cog"):
						drives[cog_id] = Vector3(-direction.x, 0, -direction.z)
			if press.get("status") != "ready" or not press.get("parts") is Dictionary:
				continue
			var fitted: Dictionary = press.parts
			for role: String in fitted:
				var id: Variant = fitted[role]
				if boxes.has(id):
					press_roles[id] = role
			if boxes.has(fitted.get("mount")) and boxes.has(fitted.get("shaft")):
				var shaft_id: String = str(fitted.shaft)
				var toward_mount: Vector3 = boxes[fitted.mount].center - boxes[shaft_id].center
				toward_mount.y = 0.0
				if toward_mount.length_squared() > 0.01:
					drives[shaft_id] = toward_mount.normalized()
			if boxes.has(fitted.get("shaft")) and boxes.has(fitted.get("drive_cog")):
				var cog_id: String = str(fitted.drive_cog)
				var toward_shaft: Vector3 = boxes[fitted.shaft].center - boxes[cog_id].center
				toward_shaft.y = 0.0
				if toward_shaft.length_squared() > 0.01:
					drives[cog_id] = toward_shaft.normalized()
	for id: String in boxes:
		var spec: Dictionary = boxes[id]
		var anchor := Node3D.new()
		anchor.name = "PlacedComponent"
		anchor.position = spec.center
		var support_drop := 0.0
		if collector_floors.has(id) and spec.component in ["tool_mount", "cutting_edge"] \
				and press_roles.get(id, "") != "mount":
			var cell: Array = placed[id].center
			var head_y := float(cell[1]) * UNIT + Geometry.ANCHOR_HEIGHT \
				+ (0.10 if spec.component == "tool_mount" else -0.015)
			var floor_y: float = collector_floors[id]
			var face_span: float = spec.size.x if absf(cos(float(collector_facings[id]))) > 0.5 else spec.size.z
			var needed_span := 0.42 if spec.component == "tool_mount" else 0.405
			var head_top := head_y + (0.18 if spec.component == "tool_mount" else 0.12)
			if absf(spec.center.y - spec.size.y * 0.5 - floor_y) < 0.001 \
					and spec.center.y + spec.size.y * 0.5 + 0.001 >= head_top \
					and face_span + 0.001 >= needed_span \
					and absf(spec.center.x - float(cell[0]) * UNIT) < 0.001 \
					and absf(spec.center.z - float(cell[2]) * UNIT) < 0.001:
				anchor.position.y = head_y
				support_drop = head_y - floor_y
		anchor.set_meta("component_entity", id)
		anchor.set_meta("component_kind", spec.component)
		add_child(anchor)
		_placed_component(anchor, spec.component, drives.get(id, Vector3.ZERO),
			spec.size, press_roles.get(id, ""), float(collector_facings.get(id, 0.0)),
			support_drop)

func _render_receiver_chutes(snapshot: Dictionary) -> void:
	# A chute joins only a native ready receiver to a native belt endpoint at
	# the next full tile. It never creates a material link or a cargo image.
	var placed: Variant = snapshot.get("placed_components", {})
	var collectors: Variant = snapshot.get("collector_assemblies", [])
	var spans: Variant = snapshot.get("belt_spans", {})
	var parts: Variant = snapshot.get("transmission_parts", {})
	if not placed is Dictionary or not collectors is Array or not spans is Dictionary or not parts is Dictionary:
		return
	for collector: Variant in collectors:
		if not collector is Dictionary or collector.get("status") != "ready" or not collector.get("parts") is Dictionary:
			continue
		var frame: Variant = placed.get(collector.parts.get("frame"))
		var receiver: Variant = placed.get(collector.parts.get("receiver"))
		if not frame is Dictionary or not receiver is Dictionary or not frame.get("center") is Array or not receiver.get("center") is Array:
			continue
		var frame_grid: Array = frame.center
		var receiver_grid: Array = receiver.center
		if frame_grid.size() != 3 or receiver_grid.size() != 3:
			continue
		var mouth: Array = []
		for axis in 3:
			mouth.append(int(frame_grid[axis]) + 4 * (int(receiver_grid[axis]) - int(frame_grid[axis])))
		for span_id: Variant in spans:
			var span: Variant = spans[span_id]
			if not span is Dictionary:
				continue
			var first: Variant = parts.get(span.get("from"))
			var last: Variant = parts.get(span.get("to"))
			if not first is Dictionary or not last is Dictionary or not first.get("center") is Array or not last.get("center") is Array:
				continue
			var endpoint: Array = first.center if first.center == mouth else last.center if last.center == mouth else []
			if endpoint.is_empty():
				continue
			var tray_at := world_center(receiver_grid)
			var belt_at := world_center(endpoint)
			var direction := belt_at - tray_at
			direction.y = 0.0
			if direction.length() < 0.5:
				continue
			direction = direction.normalized()
			var start := tray_at + direction * 0.17
			var finish := belt_at - direction * 0.27
			var length := start.distance_to(finish)
			if length < 0.15:
				continue
			var chute := Node3D.new()
			chute.name = "CollectorReceiverChute"
			chute.set_meta("receiver_entity", collector.parts.receiver)
			chute.set_meta("belt_span", span_id)
			chute.position = (start + finish) * 0.5
			chute.rotation.y = atan2(direction.x, direction.z)
			add_child(chute)
			var pan_finish: Material = Finish.material("cast", Color("354442"), 0.72, 0.52)
			var edge_finish: Material = Finish.material("worked", Color("9aaba5"), 0.78, 0.36)
			_support_box(chute, "ReceiverChuteBed", Vector3(0, 0.025, 0), Vector3(0.31, 0.035, length), pan_finish, true)
			for side in [-1.0, 1.0]:
				_support_box(chute, "ReceiverChuteLip", Vector3(side * 0.165, 0.075, 0),
					Vector3(0.025, 0.13, length), edge_finish, true)

func refresh() -> void:
	if _host == null or not is_instance_valid(_host.get_ref()):
		_clear()
		_clear_motion()
		_view_key = null
		visible = false
		return
	var snapshot: Variant = _host.get_ref().get("state")
	var options: Variant = snapshot.get("options") if snapshot is Dictionary else null
	if not snapshot is Dictionary or not options is Dictionary or typeof(options.get("native")) != TYPE_BOOL or not options.native:
		_clear()
		_clear_motion()
		_view_key = null
		visible = false
		return
	var parts: Variant = snapshot.get("transmission_parts")
	var motions: Variant = snapshot.get("motion", {})
	var component_result: Dictionary = Geometry.component_boxes(snapshot)
	if not parts is Dictionary or not motions is Dictionary or not component_result.get("accepted", false):
		_clear()
		_clear_motion()
		_view_key = null
		visible = false
		return
	visible = true
	var native_model: bool = _host.get_ref().get("model") is NativeModel
	var native_revision: Variant = snapshot.get("revision")
	var native_context: String = str(snapshot.get("context", ""))
	# Native World increments revision for every changed snapshot. Reuse the
	# already-rendered topology between cuts without walking hundreds of parts.
	if native_model and typeof(native_revision) == TYPE_INT and native_context == _native_view_context and native_revision == _native_view_revision:
		return
	var spans: Variant = snapshot.get("belt_spans", {})
	var fixed_spans := {}
	if spans is Dictionary:
		for id: Variant in spans:
			var span: Variant = spans[id]
			fixed_spans[id] = [span.get("generation"), span.get("from"), span.get("to")] if span is Dictionary else span
	var next_key := [snapshot.get("context"), parts, motions, fixed_spans,
		snapshot.get("engagements", []), snapshot.get("dropped_material", []),
		component_result.boxes, snapshot.get("collector_assemblies", []), snapshot.get("press_assemblies", [])]
	if next_key == _view_key:
		_native_view_context = native_context if native_model else ""
		_native_view_revision = native_revision if native_model else null
		_refresh_belt_cargo(spans)
		return
	var gear_count := 0
	for part: Variant in parts.values():
		if _valid_part(part) and part.kind == "gear":
			gear_count += 1
	var batch_gears := gear_count >= GEAR_BATCH_THRESHOLD
	# Native revisions identify confirmed topology. Keep identical batched pick
	# bodies across cuts; the changing MultiMesh and support batches rebuild below.
	var reused_gears: Dictionary = {}
	var retained_nodes: Dictionary = {}
	if native_model and native_context == _native_view_context and batch_gears:
		for id: Variant in parts:
			var part: Variant = parts[id]
			if typeof(id) != TYPE_STRING or not part is Dictionary or part.get("kind") != "gear" \
					or not _gear_anchor_cache.has(id):
				continue
			var cached: Dictionary = _gear_anchor_cache[id]
			var old_anchor: Variant = cached.get("anchor")
			if cached.part == part and is_instance_valid(old_anchor) and old_anchor is Node3D \
					and old_anchor.get_parent() == self:
				reused_gears[id] = cached
				retained_nodes[old_anchor.get_instance_id()] = true
	_sync_motion(snapshot)
	_clear(retained_nodes)
	# Projections can mutate their dictionaries after this call. Keep an owned
	# snapshot so a later motion or topology change cannot change the baseline.
	_view_key = next_key.duplicate(true)
	_native_view_context = native_context if native_model else ""
	_native_view_revision = native_revision if native_model else null
	_render_placed_components(snapshot, component_result.boxes)
	_render_receiver_chutes(snapshot)
	var drops: Variant = snapshot.get("dropped_material", [])
	if drops is Array:
		for drop: Variant in drops:
			if not drop is Dictionary or not drop.get("center") is Array or drop.center.size() != 3 or typeof(drop.get("raw")) != TYPE_INT or drop.raw < 0 or typeof(drop.get("products")) != TYPE_INT or drop.products < 0 or not drop.get("work_lots") is Array or (drop.raw == 0 and drop.products == 0 and drop.work_lots.is_empty()):
				continue
			var location := world_center(drop.center)
			var visual: Node3D
			if drop.raw > 0:
				visual = _cylinder(self, "LooseBlank", 0.15, 0.08, Color("b9a88c"))
				visual.position = location
			elif drop.products > 0:
				visual = Items.stamped_plate(self, location)
			else:
				visual = Items.workpiece_billet(self, location)
			var label := Label3D.new()
			label.text = "%d blank(s), %d plate(s), %d workpiece(s) · pick up in menu" % [drop.raw, drop.products, drop.work_lots.size()]
			label.position.y = 0.3
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			visual.add_child(label)
	var rendered: Dictionary = {}
	var gear_anchors: Dictionary = {}
	var direction_poses: Dictionary = {1: [], -1: []}
	var support_groups: Dictionary = {}
	for id: Variant in parts:
		var part: Variant = parts[id]
		if typeof(id) != TYPE_STRING or not _valid_part(part):
			continue
		var reused: bool = reused_gears.has(id)
		var anchor: Node3D = reused_gears[id].anchor if reused else Node3D.new()
		if not reused:
			anchor.name = "Part%d" % rendered.size()
			anchor.set_meta("entity", id)
			anchor.set_meta("kind", part.kind)
			if part.kind in ["gear", "shaft"]:
				anchor.set_meta("axis", part.axis)
			anchor.position = world_center(part.center)
			anchor.basis = axis_basis(part.axis) if part.kind in ["gear", "shaft"] else Basis.IDENTITY
			add_child(anchor)
		var style := ""
		if batch_gears:
			style = str(reused_gears[id].style) if reused else _support_style(part)
			if not style.is_empty():
				if not support_groups.has(style):
					support_groups[style] = {"part": part, "id": id, "poses": []}
				support_groups[style].poses.append(Transform3D(Basis.IDENTITY, anchor.position))
		else:
			_confirmed_support(id, part)
		rendered[id] = anchor
		var motion: Variant = motions.get(id, {})
		var rotating: bool = motion is Dictionary and motion.get("state") == "rotating" and typeof(motion.get("numerator")) == TYPE_INT and typeof(motion.get("denominator")) == TYPE_INT and motion.denominator > 0 and motion.numerator != 0
		anchor.set_meta("motion_state", motion.get("state", "unknown") if motion is Dictionary else "unknown")
		var color := Color("687a7b")
		if part.kind == "gear":
			var radius: float = Geometry.PITCH / 2.0
			if batch_gears:
				if not reused:
					anchor.set_meta("batched_gear", true)
				_batched_gear_ids[id] = true
				if not gear_anchors.has(part.teeth):
					gear_anchors[part.teeth] = []
				gear_anchors[part.teeth].append(anchor)
				_gear_anchor_cache[id] = {"part": reused_gears[id].part if reused else part.duplicate(true),
					"anchor": anchor, "style": style}
			else:
				Assets.gear(anchor, radius, part.teeth, color)
				Assets.shaft(anchor, Geometry.PITCH, color)
			if not reused:
				_pick(anchor, id, radius, 0.24, Geometry.PITCH)
			if rotating:
				var sign_value := 1 if motion.numerator > 0 else -1
				if batch_gears:
					direction_poses[sign_value].append(Transform3D(anchor.basis, anchor.position))
				else:
					_direction(anchor, radius * 0.65, sign_value)
		elif part.kind == "shaft":
			var length: float = float(part.half_span) * UNIT * 2.0
			Assets.shaft(anchor, length, color)
			var keyway := MeshInstance3D.new()
			keyway.name = "Keyway"
			var key_shape := BoxMesh.new()
			key_shape.size = Vector3(0.012, length * 0.92, 0.006)
			keyway.mesh = key_shape
			keyway.position.z = Assets.SHAFT_CORE_RADIUS
			_finish(keyway, Color("e2c58a"))
			anchor.add_child(keyway)
			_pick(anchor, id, 0.08, length)
		else:
			_relay_case(anchor, id, part)
	if batch_gears:
		for style: String in support_groups:
			var group: Dictionary = support_groups[style]
			var support_mesh := _support_mesh(group.part, group.id, style)
			if support_mesh != null:
				var poses: Array[Transform3D] = []
				poses.assign(group.poses)
				_add_batch(support_mesh, poses, "SupportBatch")
		for teeth: int in gear_anchors:
			var anchors: Array = gear_anchors[teeth]
			var poses: Array[Transform3D] = []
			var ids: Array[String] = []
			var bases: Array[Basis] = []
			var origins: Array[Vector3] = []
			for anchor: Node3D in anchors:
				poses.append(anchor.transform)
				ids.append(str(anchor.get_meta("entity")))
				bases.append(axis_basis(int(anchor.get_meta("axis"))))
				origins.append(anchor.position)
			var mesh := Assets.complete_gear_mesh(Geometry.PITCH / 2.0, teeth,
				Color("687a7b"), Geometry.PITCH)
			var last_angles: Array[float] = []
			last_angles.resize(ids.size())
			_gear_batches[teeth] = {"mesh": _add_batch(mesh, poses, "CogBatch%d" % teeth),
				"anchors": anchors, "ids": ids, "bases": bases, "origins": origins,
				"last_angles": last_angles}
		for sign_value: int in direction_poses:
			var poses: Array[Transform3D] = []
			poses.assign(direction_poses[sign_value])
			if not poses.is_empty():
				_add_batch(_direction_mesh(Geometry.PITCH * 0.325, sign_value), poses,
					"DirectionBatch%d" % sign_value)
	if spans is Dictionary:
		for id: Variant in spans:
			if typeof(id) == TYPE_STRING:
				_belt_span(id, spans[id], parts, rendered)
	# Contact marks come only from confirmed gear engagements, never a second
	# proximity solver or an arbitrary decorative power edge.
	var engagements: Variant = snapshot.get("engagements", [])
	if engagements is Array:
		for edge: Variant in engagements:
			if not edge is Dictionary or not rendered.has(edge.get("a")) or not rendered.has(edge.get("b")):
				continue
			var a: Dictionary = parts[edge.a]
			var b: Dictionary = parts[edge.b]
			if typeof(edge.get("kind")) == TYPE_INT and edge.kind == 1:
				if a.kind == "shaft" and b.kind == "gear":
					_shaft_coupling(a, b, rendered[edge.a], edge.a, edge.b)
				elif b.kind == "shaft" and a.kind == "gear":
					_shaft_coupling(b, a, rendered[edge.b], edge.b, edge.a)
				elif a.kind == "shaft" and b.kind == "shaft":
					_shaft_splice(a, b, rendered[edge.a], edge.a, edge.b)
				continue
			if a.kind != "gear" or b.kind != "gear":
				continue
			var mark := _cylinder(self, "ConfirmedEngagement", 0.06, 0.07, Color("9bc883"))
			mark.position = world_center(a.center).lerp(world_center(b.center), float(a.teeth) / float(a.teeth + b.teeth))
			mark.basis = axis_basis(a.axis)
			mark.set_meta("from", edge.a)
			mark.set_meta("to", edge.b)
	# Topology changes rebuild this list. A dense cog batch has pick anchors
	# but no individual animated scene nodes to scan each render frame.
	for child in get_children():
		if child is Node3D and not child.get_meta("batched_gear", false) and (child.has_meta("axis")
				or child.has_meta("belt_shaft") or child.has_meta("relay_static")):
			_moving_anchors.append(child)
	_apply_angles()
	_refresh_belt_cargo(spans)
