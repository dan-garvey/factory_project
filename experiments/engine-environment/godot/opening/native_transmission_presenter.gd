extends Node3D
## Confirmed geometry/rates with cosmetic angles only. No simulation clock,
## saved/contact phase, material operation or actor collider.
const Geometry = preload("res://opening/site_geometry.gd")
const Assets = preload("res://opening/native_transmission_assets.gd")
const Items = preload("res://opening/workpiece_item_assets.gd")
const Finish = preload("res://opening/opening.gd").ProductionTransmissionFinish
const UNIT := Geometry.PITCH / 4.0
## The native lane moves one horizontal tile per 0.45-second tick at rate 1.
## Its pulley rim must travel the same distance in that time.
const VISUAL_RADIANS_PER_SECOND := Geometry.PITCH / (Assets.SPAN_OUTER_RADIUS * 0.45)
const BELT_SUBTICKS_PER_TILE := 4096.0 # Matches the native material lane's fixed-point denominator.

var _host: WeakRef
var _view_key := ""
var _cargo_keys: Dictionary = {}
var _motion_context := ""
var _generations: Dictionary = {}
var _visual_angles: Dictionary = {}
var _visual_rotations: Dictionary = {}

func configure(host: Object) -> void:
	_host = weakref(host)
	_view_key = ""
	_clear_motion()
	refresh()

func _clear() -> void:
	_cargo_keys.clear()
	for child in get_children():
		child.free()

func _clear_motion() -> void:
	_motion_context = ""
	_generations.clear()
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

static func signed_rate(motion: Variant) -> float:
	if not motion is Dictionary or motion.get("state") != "rotating" or typeof(motion.get("numerator")) != TYPE_INT or typeof(motion.get("denominator")) != TYPE_INT or motion.denominator <= 0:
		return 0.0
	return float(motion.numerator) / float(motion.denominator)

func visual_angle(id: String) -> float:
	return float(_visual_angles.get(id, 0.0))

func visual_rotation(id: String) -> float:
	return float(_visual_rotations.get(id, 0.0))

func _apply_angles() -> void:
	for child: Node in get_children():
		if child is Node3D and child.has_meta("belt_shaft"):
			var loop := child.get_node_or_null("BeltLoop") as MeshInstance3D
			if loop != null and loop.material_override is StandardMaterial3D:
				var finish := loop.material_override as StandardMaterial3D
				var offset := float(child.get_meta("belt_uv_origin")) + visual_rotation(str(child.get_meta("belt_shaft"))) * float(child.get_meta("belt_uv_factor"))
				finish.uv1_offset.x = fposmod(offset, 1.0)
		if not child is Node3D or not child.has_meta("axis"):
			continue
		var id: String = str(child.get_meta("entity", ""))
		var angle := visual_angle(id)
		child.basis = axis_basis(int(child.get_meta("axis"))) * Basis(Vector3.UP, angle)
		var arrow := child.get_node_or_null("ConfirmedDirection")
		if arrow != null:
			# Keep the signed-rate annotation fixed while its rotor turns.
			arrow.rotation.y = -angle

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
	_sync_motion(snapshot)
	for id: String in _generations:
		var rate := signed_rate(snapshot.motion.get(id))
		if rate != 0.0:
			var step := delta * rate * VISUAL_RADIANS_PER_SECOND
			if not is_finite(step) or not is_finite(visual_rotation(id) + step):
				continue
			_visual_rotations[id] = visual_rotation(id) + step
			_visual_angles[id] = wrapf(visual_angle(id) + step, -PI, PI)
	_apply_angles()

static func axis_basis(axis: int) -> Basis:
	match axis:
		0: return Basis(Vector3.DOWN, Vector3.RIGHT, Vector3.BACK)
		2: return Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN)
	return Basis.IDENTITY

static func world_center(center: Array) -> Vector3:
	return Vector3(center[0] * UNIT, Geometry.ANCHOR_HEIGHT + center[1] * UNIT, center[2] * UNIT)

func _valid_part(part: Variant) -> bool:
	if not part is Dictionary or part.get("kind") not in ["gear", "shaft"]:
		return false
	if typeof(part.get("axis")) != TYPE_INT or part.axis not in [0, 1, 2]:
		return false
	var center: Variant = part.get("center")
	if not center is Array or center.size() != 3:
		return false
	for value: Variant in center:
		if typeof(value) != TYPE_INT or value < -1048576 or value > 1048576:
			return false
	var size: Variant = part.get("teeth" if part.kind == "gear" else "half_span")
	return typeof(size) == TYPE_INT and size > 0 and size <= 256

func _support_point(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for coordinate: Variant in value:
		if typeof(coordinate) != TYPE_FLOAT or not is_finite(coordinate):
			return false
	return true

func _confirmed_support(id: String, part: Dictionary) -> void:
	var support: Variant = part.get("support")
	if not support is Dictionary or not _support_point(support.get("foot")) or not _support_point(support.get("bearing")):
		return
	var foot := Vector3(support.foot[0], support.foot[1], support.foot[2])
	var bearing := Vector3(support.bearing[0], support.bearing[1], support.bearing[2])
	if bearing.y <= foot.y or bearing.y - foot.y > 9.0:
		return
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
	var height: float = bearing.y - foot.y
	var across: Vector3 = Vector3.FORWARD if part.axis == 0 else Vector3.RIGHT
	var side: Vector3 = Vector3.UP.cross(across)
	# The visual frame stays near the one native-confirmed support point. These
	# braces do not claim extra terrain seats, clearance or structural strength.
	if height < 0.48:
		_support_box(frame, "CompactPedestal", (foot + bearing) * 0.5,
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
	if height >= 0.48:
		_support_box(frame, "BearingSaddle", bearing - Vector3.UP * 0.075,
			Vector3(0.31, 0.15, 0.31), cast)
		var socket := _support_cylinder(frame, "BearingHousing", 0.16, 0.23, dark)
		socket.position = bearing
		socket.basis = axis_basis(part.axis)
		var rim := _support_cylinder(frame, "MachinedBearingRim", 0.185, 0.045, worked)
		rim.position = bearing + axis_basis(part.axis).y * 0.13
		rim.basis = socket.basis
	else:
		_support_box(frame, "LowBearingCap", bearing - Vector3.UP * minf(0.03, height * 0.5),
			Vector3(0.23, minf(0.06, height), 0.23), worked)
	_support_beam(frame, "AxleBridge", bearing, world_center(part.center), 0.095, worked)

func _support_box(parent: Node3D, name_value: String, at: Vector3, size: Vector3,
		material: Material) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = name_value
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.position = at
	mesh.material_override = material
	parent.add_child(mesh)

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
		width: float, material: Material) -> void:
	var direction := b - a
	if direction.length_squared() < 0.000001:
		return
	var mesh := MeshInstance3D.new()
	mesh.name = name_value
	var shape := BoxMesh.new()
	shape.size = Vector3(width, direction.length(), width)
	mesh.mesh = shape
	var along := direction.normalized()
	var reference := Vector3.RIGHT if absf(along.dot(Vector3.RIGHT)) < 0.95 else Vector3.BACK
	var across := reference.cross(along).normalized()
	mesh.basis = Basis(across, along, across.cross(along))
	mesh.position = (a + b) * 0.5
	mesh.material_override = material
	parent.add_child(mesh)

func _finish(mesh: MeshInstance3D, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.65
	material.roughness = 0.4
	mesh.material_override = material

func _cylinder(parent: Node3D, name_value: String, radius: float, height: float, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = name_value
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 24
	mesh.mesh = shape
	_finish(mesh, color)
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
	add_child(anchor)
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
	for anchor: Node in get_children():
		if not anchor is Node3D or anchor.get_meta("kind", "") != "belt_span":
			continue
		var id: String = anchor.get_meta("entity", "")
		var span: Variant = spans.get(id)
		if not span is Dictionary:
			continue
		var slots: Variant = span.get("slots", [])
		var cargo_key := JSON.stringify([slots, span.get("phase")])
		if _cargo_keys.get(id) == cargo_key:
			continue
		_cargo_keys[id] = cargo_key
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

func refresh() -> void:
	if _host == null or not is_instance_valid(_host.get_ref()):
		_clear()
		_clear_motion()
		_view_key = ""
		visible = false
		return
	var snapshot: Variant = _host.get_ref().get("state")
	var options: Variant = snapshot.get("options") if snapshot is Dictionary else null
	if not snapshot is Dictionary or not options is Dictionary or typeof(options.get("native")) != TYPE_BOOL or not options.native:
		_clear()
		_clear_motion()
		_view_key = ""
		visible = false
		return
	var parts: Variant = snapshot.get("transmission_parts")
	var motions: Variant = snapshot.get("motion", {})
	if not parts is Dictionary or not motions is Dictionary:
		_clear()
		_clear_motion()
		_view_key = ""
		visible = false
		return
	visible = true
	_sync_motion(snapshot)
	var spans: Variant = snapshot.get("belt_spans", {})
	var fixed_spans := {}
	if spans is Dictionary:
		for id: Variant in spans:
			var span: Variant = spans[id]
			fixed_spans[id] = [span.get("generation"), span.get("from"), span.get("to")] if span is Dictionary else span
	var next_key := JSON.stringify([snapshot.get("context"), parts, motions, fixed_spans, snapshot.get("engagements", []), snapshot.get("dropped_material", [])])
	if next_key == _view_key:
		_refresh_belt_cargo(spans)
		return
	_clear()
	_view_key = next_key
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
	for id: Variant in parts:
		var part: Variant = parts[id]
		if typeof(id) != TYPE_STRING or not _valid_part(part):
			continue
		var anchor := Node3D.new()
		anchor.name = "Part%d" % rendered.size()
		anchor.set_meta("entity", id)
		anchor.set_meta("kind", part.kind)
		anchor.set_meta("axis", part.axis)
		anchor.position = world_center(part.center)
		anchor.basis = axis_basis(part.axis)
		add_child(anchor)
		_confirmed_support(id, part)
		rendered[id] = anchor
		var motion: Variant = motions.get(id, {})
		var rotating: bool = motion is Dictionary and motion.get("state") == "rotating" and typeof(motion.get("numerator")) == TYPE_INT and typeof(motion.get("denominator")) == TYPE_INT and motion.denominator > 0 and motion.numerator != 0
		anchor.set_meta("motion_state", motion.get("state", "unknown") if motion is Dictionary else "unknown")
		var color := Color("687a7b")
		if part.kind == "gear":
			var radius: float = Geometry.PITCH / 2.0
			Assets.gear(anchor, radius, part.teeth, color)
			Assets.shaft(anchor, Geometry.PITCH, color)
			_pick(anchor, id, radius, 0.24, Geometry.PITCH)
			if rotating:
				_direction(anchor, radius * 0.65, 1 if motion.numerator > 0 else -1)
		else:
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
	_apply_angles()
	_refresh_belt_cargo(spans)
