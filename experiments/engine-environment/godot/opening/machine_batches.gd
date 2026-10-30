extends RefCounted
## Draw batching and mesh caches only. Rebuild takes the rendered root and motion anchors.
const Geometry = preload("res://opening/site_geometry.gd")
const PITCH = Geometry.PITCH
const ProductionConveyorArt = preload("res://opening/production_conveyors.gd").ProductionConveyorArt
const MACHINE_BATCH_THRESHOLD := 12
const MACHINE_STATIC_SPATIAL_THRESHOLD := 256
const MACHINE_STATIC_SPATIAL_FIELD_THRESHOLD := 800
const WHEEL_ROTOR_BATCH_CELL := 32.0

var machine_root: Node3D
var machine_motion_anchors: Array[Node3D] = []
var machine_dynamic_batches: Array[Dictionary] = []
var machine_conveyor_batches: Array[Dictionary] = []
var machine_conveyor_batch_slots: Dictionary = {}
var machine_batched_rotors: Dictionary = {}
var machine_batched_rotor_slots: Dictionary = {}
var machine_cutter_batch_slots: Dictionary = {}
var wheel_batch_poses: Dictionary = {}
var wheel_updated_rotors: Dictionary = {}
var machine_batch_finished_meshes: Dictionary = {}
var machine_batch_rotor_meshes: Dictionary = {}
var machine_batch_composite_meshes: Dictionary = {}
var machine_static_spatial_tiles: int = 4 if OS.has_feature("windows") else 0
var machine_batch_static_machine_count := 0
static var _varied_planar_shader: Shader
static var _varied_triplanar_shader: Shader
static var _varied_plain_shader: Shader
static var _consolidated_materials: Dictionary = {}

static func cutter_pose(anchor: Node3D, angle: float) -> Transform3D:
	var pivot := Vector3(-0.22, 1.1, -0.19)
	var axle := Vector3.BACK
	if anchor.get_meta("material_rotated", false):
		var turn := Basis(Vector3.UP, -PI / 2.0)
		pivot = turn * pivot
		axle = turn * axle
	var spin := Transform3D(Basis(axle, angle), Vector3.ZERO)
	spin.origin = pivot - spin.basis * pivot
	return spin

func _machine_batch_surface_mesh(part: MeshInstance3D) -> Mesh:
	var source: Mesh = part.mesh
	var finishes: Array = []
	var finish_ids: Array[int] = []
	var has_overrides := false
	for surface in source.get_surface_count():
		var finish: Material = part.get_surface_override_material(surface)
		has_overrides = has_overrides or finish != null
		if finish == null:
			finish = source.surface_get_material(surface)
		finishes.append(finish)
		finish_ids.append(finish.get_instance_id() if finish != null else 0)
	if not has_overrides:
		return source
	var key := [source.get_instance_id(), finish_ids]
	if machine_batch_finished_meshes.has(key):
		return machine_batch_finished_meshes[key]
	var result := ArrayMesh.new()
	for surface in source.get_surface_count():
		result.add_surface_from_arrays(source.surface_get_primitive_type(surface),
			source.surface_get_arrays(surface))
		result.surface_set_material(surface, finishes[surface])
	machine_batch_finished_meshes[key] = result
	return result

func _collect_wheel_rotor_parts(node: Node3D, pose: Transform3D, parts: Array[Dictionary]) -> bool:
	for child in node.get_children():
		if not child is Node3D or not child.visible:
			continue
		var child_pose: Transform3D = pose * (child as Node3D).transform
		if child is MeshInstance3D:
			var part := child as MeshInstance3D
			if part.mesh == null or part.material_overlay != null:
				return false
			if part.visibility_range_end > 0.0:
				continue
			for surface in part.mesh.get_surface_count():
				var finish: Material = part.material_override
				if finish == null:
					finish = part.get_surface_override_material(surface)
				if finish == null:
					finish = part.mesh.surface_get_material(surface)
				if finish is BaseMaterial3D and finish.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					return false
				if part.mesh is ArrayMesh and part.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
					return false
				parts.append({"source": part, "mesh": part.mesh, "surface": surface, "finish": finish,
					"pose": child_pose, "shadow": part.cast_shadow, "layers": part.layers})
		if not _collect_wheel_rotor_parts(child, child_pose, parts):
			return false
	return true

func _wheel_rotor_batch_mesh(rotor: Node3D, hidden_core: Array[MeshInstance3D]) -> Mesh:
	var key: Array = rotor.get_meta("visual_batch_key", [])
	var parts: Array[Dictionary] = []
	if not _collect_wheel_rotor_parts(rotor, Transform3D.IDENTITY, parts) or parts.is_empty():
		return null
	for part in parts:
		if part.source not in hidden_core:
			hidden_core.append(part.source)
	if machine_batch_rotor_meshes.has(key):
		return machine_batch_rotor_meshes[key]
	var groups := {}
	var shadow: int = parts[0].shadow
	var layers: int = parts[0].layers
	for part in parts:
		if part.shadow != shadow or part.layers != layers:
			return null
		var finish: Material = part.finish
		var finish_id := finish.get_instance_id() if finish != null else 0
		if not groups.has(finish_id):
			groups[finish_id] = {"finish": finish, "parts": []}
		groups[finish_id].parts.append(part)
	var combined: ArrayMesh
	for group in groups.values():
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part in group.parts:
			surface.append_from(part.mesh, part.surface, part.pose)
		surface.set_material(group.finish)
		combined = surface.commit(combined)
	combined = finish_mesh(combined, true)
	machine_batch_rotor_meshes[key] = combined
	return combined

func _collect_machine_composite_parts(node: Node3D, pose: Transform3D,
		moving: Dictionary, parts: Array[Dictionary]) -> void:
	# Keep moving, translucent, range-culled and conveyor-loop visuals on their
	# existing paths. Only identical opaque static assemblies can be instanced.
	for child in node.get_children():
		if not child is Node3D or not child.visible or child.name == "WheelRotor":
			continue
		var child_pose: Transform3D = pose * child.transform
		if child is MeshInstance3D:
			var source := child as MeshInstance3D
			if moving.has(source.get_instance_id()):
				continue
			# Hiding a scene parent would also hide its unbatched children.
			if source.mesh != null and source.get_child_count() == 0 and source.name != "ConveyorLoop" \
					and source.material_overlay == null \
					and source.visibility_range_end <= 0.0:
				var eligible_parts: Array[Dictionary] = []
				for surface in source.mesh.get_surface_count():
					var finish: Material = source.material_override
					if finish == null:
						finish = source.get_surface_override_material(surface)
					if finish == null:
						finish = source.mesh.surface_get_material(surface)
					if (finish is BaseMaterial3D and finish.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED) \
							or (source.mesh is ArrayMesh and source.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES):
						eligible_parts.clear()
						break
					eligible_parts.append({"source": source, "mesh": source.mesh, "surface": surface,
						"finish": finish, "pose": child_pose, "shadow": source.cast_shadow,
						"layers": source.layers})
				parts.append_array(eligible_parts)
		_collect_machine_composite_parts(child, child_pose, moving, parts)

func _machine_finish_mesh(source: ArrayMesh) -> ArrayMesh:
	return finish_mesh(source, false)

static func finish_mesh(source: ArrayMesh, allow_extended: bool = false) -> ArrayMesh:
	if source == null or source.get_surface_count() == 0 or (not allow_extended and source.get_surface_count() <= 1):
		return source
	# Opaque parts can share a surface when their finish differs only by values
	# carried on vertices. Keep unsupported surfaces intact when allow_extended is set.
	var groups := {}
	var passthrough: Array[int] = []
	for surface_index in source.get_surface_count():
		var raw_mat := source.surface_get_material(surface_index)
		var finish := raw_mat as StandardMaterial3D
		if allow_extended and finish == null and raw_mat is ShaderMaterial and source.surface_get_primitive_type(surface_index) == Mesh.PRIMITIVE_TRIANGLES:
			var s_arrays := source.surface_get_arrays(surface_index)
			var s_pts: PackedVector3Array = s_arrays[Mesh.ARRAY_VERTEX]
			var s_norms: PackedVector3Array = s_arrays[Mesh.ARRAY_NORMAL]
			var s_cols = s_arrays[Mesh.ARRAY_COLOR]
			var s_uv2 = s_arrays[Mesh.ARRAY_TEX_UV2]
			var s_idx = s_arrays[Mesh.ARRAY_INDEX]
			var s_uv = s_arrays[Mesh.ARRAY_TEX_UV]
			var s_tan = s_arrays[Mesh.ARRAY_TANGENT]
			if s_norms.size() == s_pts.size() and s_cols is PackedColorArray and s_cols.size() == s_pts.size():
				var s_key := [true, 3]
				if not groups.has(s_key):
					groups[s_key] = {"finish": null, "varied": true, "mode": 3, "key": s_key, "vertices": [],
						"normals": [], "tangents": [], "uv": [], "uv2": [], "colors": [], "indices": []}
				var s_group: Dictionary = groups[s_key]
				var s_start: int = s_group.vertices.size()
				for pi in s_pts.size():
					s_group.vertices.append(s_pts[pi])
					s_group.normals.append(s_norms[pi])
					s_group.uv.append(s_uv[pi] if (s_uv is PackedVector2Array and s_uv.size() == s_pts.size()) else Vector2.ZERO)
					if s_tan is PackedFloat32Array and s_tan.size() == s_pts.size() * 4:
						for lane in 4:
							s_group.tangents.append(s_tan[pi * 4 + lane])
					else:
						s_group.tangents.append(1.0)
						s_group.tangents.append(0.0)
						s_group.tangents.append(0.0)
						s_group.tangents.append(1.0)
					s_group.colors.append(s_cols[pi])
					var r_val := float(s_uv2[pi].x) if (s_uv2 is PackedVector2Array and s_uv2.size() == s_pts.size()) else 0.55
					if r_val >= 0.98:
						r_val = 0.52
					s_group.uv2.append(Vector2(r_val, 0.0))
				if not s_idx is PackedInt32Array or s_idx.is_empty():
					for pi in s_pts.size():
						s_group.indices.append(s_start + pi)
				else:
					for pi in s_idx:
						s_group.indices.append(s_start + pi)
				continue
		if finish == null or finish.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
				or finish.albedo_texture != null \
				or source.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
			if allow_extended:
				passthrough.append(surface_index)
				continue
			return source
		var arrays := source.surface_get_arrays(surface_index)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var tangents = arrays[Mesh.ARRAY_TANGENT]
		var uv = arrays[Mesh.ARRAY_TEX_UV]
		var colors = arrays[Mesh.ARRAY_COLOR]
		var indices = arrays[Mesh.ARRAY_INDEX]
		var varied_plain: bool = allow_extended
		var has_tangents_uv: bool = normals.size() == points.size() and tangents is PackedFloat32Array \
			and tangents.size() == points.size() * 4 and uv is PackedVector2Array \
			and uv.size() == points.size()
		if not has_tangents_uv and not (varied_plain and normals.size() == points.size()):
			if allow_extended:
				passthrough.append(surface_index)
				continue
			return source
		var varied_planar := not varied_plain and not finish.uv1_triplanar and finish.normal_enabled \
			and finish.normal_texture != null and finish.roughness_texture != null \
			and finish.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED \
			and finish.metallic_texture == null
		var varied_triplanar := false
		var varied := varied_planar or varied_triplanar or varied_plain
		var mode := 1 if varied_planar else (2 if varied_triplanar else (3 if varied_plain else 0))
		var key := [varied, mode]
		if not varied_plain:
			for property in finish.get_property_list():
				if (int(property.usage) & PROPERTY_USAGE_STORAGE) == 0 or property.name in [
						"resource_name", "resource_path", "resource_local_to_scene",
						"albedo_color", "vertex_color_use_as_albedo"]:
					continue
				if varied and property.name in ["metallic", "roughness"]:
					continue
				key.append([property.name, finish.get(property.name)])
		var eff_roughness: float = finish.roughness
		if varied_plain and finish.roughness_texture != null and is_equal_approx(finish.roughness, 1.0):
			eff_roughness = 0.42 if finish.normal_scale > 0.5 else (0.76 if finish.normal_scale < 0.12 else 0.68)
		if not groups.has(key):
			groups[key] = {"finish": finish, "varied": varied, "mode": mode, "key": key, "vertices": [],
				"normals": [], "tangents": [], "uv": [], "uv2": [], "colors": [], "indices": []}
		var group: Dictionary = groups[key]
		var start: int = group.vertices.size()
		for point_index in points.size():
			group.vertices.append(points[point_index])
			group.normals.append(normals[point_index])
			if uv is PackedVector2Array and uv.size() == points.size():
				group.uv.append(uv[point_index])
			else:
				group.uv.append(Vector2.ZERO)
			if tangents is PackedFloat32Array and tangents.size() == points.size() * 4:
				for lane in 4:
					group.tangents.append(tangents[point_index * 4 + lane])
			else:
				group.tangents.append(1.0)
				group.tangents.append(0.0)
				group.tangents.append(0.0)
				group.tangents.append(1.0)
			var color := finish.albedo_color
			if finish.vertex_color_use_as_albedo and colors is PackedColorArray \
					and colors.size() == points.size():
				color *= colors[point_index]
			if varied:
				color.a = finish.metallic
				group.uv2.append(Vector2(eff_roughness, 0))
			group.colors.append(color)
		if not indices is PackedInt32Array or indices.is_empty():
			for point_index in points.size():
				group.indices.append(start + point_index)
		else:
			for point_index in indices:
				group.indices.append(start + point_index)
	if groups.is_empty() or (not allow_extended and groups.size() + passthrough.size() >= source.get_surface_count()):
		return source
	var result := ArrayMesh.new()
	for group in groups.values():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(group.vertices)
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(group.normals)
		arrays[Mesh.ARRAY_TANGENT] = PackedFloat32Array(group.tangents)
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(group.uv)
		if group.varied:
			arrays[Mesh.ARRAY_TEX_UV2] = PackedVector2Array(group.uv2)
		arrays[Mesh.ARRAY_COLOR] = PackedColorArray(group.colors)
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(group.indices)
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material: Material = _consolidated_materials.get(group.key)
		if material == null:
			if group.mode == 1:
				if _varied_planar_shader == null:
					_varied_planar_shader = Shader.new()
					_varied_planar_shader.code = "shader_type spatial;\n" + \
						"uniform sampler2D finish_rough : filter_linear_mipmap_anisotropic, repeat_enable;\n" + \
						"uniform sampler2D finish_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;\n" + \
						"uniform vec2 finish_uv_scale;\n" + \
						"uniform vec2 finish_uv_offset;\n" + \
						"uniform float finish_normal_scale;\n" + \
						"void fragment() { vec2 at = UV * finish_uv_scale + finish_uv_offset; " + \
						"ALBEDO = COLOR.rgb; METALLIC = COLOR.a; " + \
						"ROUGHNESS = UV2.x * texture(finish_rough, at).r; " + \
						"NORMAL_MAP = texture(finish_normal, at).rgb; " + \
						"NORMAL_MAP_DEPTH = finish_normal_scale; }"
				var custom_finish := ShaderMaterial.new()
				custom_finish.shader = _varied_planar_shader
				custom_finish.set_shader_parameter("finish_rough", group.finish.roughness_texture)
				custom_finish.set_shader_parameter("finish_normal", group.finish.normal_texture)
				custom_finish.set_shader_parameter("finish_uv_scale", Vector2(group.finish.uv1_scale.x, group.finish.uv1_scale.y))
				custom_finish.set_shader_parameter("finish_uv_offset", Vector2(group.finish.uv1_offset.x, group.finish.uv1_offset.y))
				custom_finish.set_shader_parameter("finish_normal_scale", group.finish.normal_scale)
				material = custom_finish
			elif group.mode == 2:
				if _varied_triplanar_shader == null:
					_varied_triplanar_shader = Shader.new()
					_varied_triplanar_shader.code = "shader_type spatial;\n" + \
						"uniform sampler2D finish_rough : filter_linear_mipmap_anisotropic, repeat_enable;\n" + \
						"uniform sampler2D finish_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;\n" + \
						"uniform vec3 finish_uv_scale;\n" + \
						"uniform vec3 finish_uv_offset;\n" + \
						"uniform float finish_triplanar_sharpness;\n" + \
						"uniform float finish_normal_scale;\n" + \
						"varying vec3 triplanar_pos;\n" + \
						"varying vec3 triplanar_power_normal;\n" + \
						"void vertex() {\n" + \
						"\ttriplanar_power_normal = pow(abs(NORMAL), vec3(finish_triplanar_sharpness));\n" + \
						"\ttriplanar_power_normal /= max(dot(triplanar_power_normal, vec3(1.0)), 0.00001);\n" + \
						"\ttriplanar_pos = (VERTEX * finish_uv_scale + finish_uv_offset) * vec3(1.0, -1.0, 1.0);\n" + \
						"}\n" + \
						"vec4 triplanar_tex(sampler2D s, vec3 w, vec3 p) {\n" + \
						"\treturn texture(s, p.xy) * w.z + texture(s, p.xz) * w.y + texture(s, p.zy * vec2(-1.0, 1.0)) * w.x;\n" + \
						"}\n" + \
						"void fragment() {\n" + \
						"\tALBEDO = COLOR.rgb; METALLIC = COLOR.a;\n" + \
						"\tROUGHNESS = UV2.x * triplanar_tex(finish_rough, triplanar_power_normal, triplanar_pos).r;\n" + \
						"\tNORMAL_MAP = triplanar_tex(finish_normal, triplanar_power_normal, triplanar_pos).rgb;\n" + \
						"\tNORMAL_MAP_DEPTH = finish_normal_scale;\n" + \
						"}"
				var tri_finish := ShaderMaterial.new()
				tri_finish.shader = _varied_triplanar_shader
				tri_finish.set_shader_parameter("finish_rough", group.finish.roughness_texture)
				tri_finish.set_shader_parameter("finish_normal", group.finish.normal_texture)
				tri_finish.set_shader_parameter("finish_uv_scale", group.finish.uv1_scale)
				tri_finish.set_shader_parameter("finish_uv_offset", group.finish.uv1_offset)
				tri_finish.set_shader_parameter("finish_triplanar_sharpness", group.finish.uv1_triplanar_sharpness)
				tri_finish.set_shader_parameter("finish_normal_scale", group.finish.normal_scale)
				material = tri_finish
			elif group.mode == 3:
				if _varied_plain_shader == null:
					_varied_plain_shader = Shader.new()
					_varied_plain_shader.code = "shader_type spatial;\n" + \
						"void fragment() { ALBEDO = COLOR.rgb; METALLIC = COLOR.a; ROUGHNESS = UV2.x; }"
				var plain_finish := ShaderMaterial.new()
				plain_finish.shader = _varied_plain_shader
				material = plain_finish
			else:
				var standard := group.finish.duplicate() as StandardMaterial3D
				standard.albedo_color = Color.WHITE
				standard.vertex_color_use_as_albedo = true
				material = standard
			_consolidated_materials[group.key] = material
		result.surface_set_material(result.get_surface_count() - 1, material)
	for surface_index in passthrough:
		result.add_surface_from_arrays(source.surface_get_primitive_type(surface_index),
			source.surface_get_arrays(surface_index))
		result.surface_set_material(result.get_surface_count() - 1,
			source.surface_get_material(surface_index))
	return result

func _machine_composite_mesh(parts: Array[Dictionary], key: Array) -> ArrayMesh:
	if machine_batch_composite_meshes.has(key):
		return machine_batch_composite_meshes[key]
	var finishes := {}
	for part in parts:
		var finish: Material = part.finish
		var finish_id := finish.get_instance_id() if finish != null else 0
		if not finishes.has(finish_id):
			finishes[finish_id] = {"material": finish, "parts": []}
		finishes[finish_id].parts.append(part)
	var combined: ArrayMesh
	for group in finishes.values():
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part in group.parts:
			surface.append_from(part.mesh, part.surface, part.pose)
		surface.set_material(group.material)
		combined = surface.commit(combined)
	combined = _machine_finish_mesh(combined)
	# Keep the full composite and its finishes at close range. Godot selects
	# simpler indices only when their projected error fits the viewport LOD.
	var importer := ImporterMesh.from_mesh(combined)
	importer.generate_lods(60.0, 60.0, [])
	combined = importer.get_mesh()
	machine_batch_composite_meshes[key] = combined
	return combined

func _batch_machine_composites(moving: Dictionary, static_groups: Dictionary,
		force_live: bool = false) -> Dictionary:
	var candidates := {}
	var skip_sources := {}
	for anchor in machine_root.get_children():
		# Wheel rotors already use a composite moving mesh; their supports did
		# not improve the rendered frame-time comparison.
		if not anchor is Node3D or not anchor.has_meta("machine_kind") \
				or (not force_live and anchor.get_meta("machine_kind") == "wheel"):
			continue
		var parts: Array[Dictionary] = []
		_collect_machine_composite_parts(anchor, Transform3D.IDENTITY, moving, parts)
		if parts.size() < 2:
			continue
		var shadow: int = parts[0].shadow
		var layers: int = parts[0].layers
		var key: Array = []
		var compatible := true
		for part in parts:
			if part.shadow != shadow or part.layers != layers:
				compatible = false
				break
			var finish: Material = part.finish
			key.append_array([part.mesh.get_instance_id(), part.surface,
				finish.get_instance_id() if finish != null else 0, part.pose])
		if not compatible:
			continue
		key.append_array([shadow, layers])
		if not candidates.has(key):
			candidates[key] = {"parts": parts, "instances": []}
		candidates[key].instances.append({"anchor": anchor, "parts": parts})
	for key in candidates:
		var candidate: Dictionary = candidates[key]
		if candidate.instances.size() < (1 if force_live else 2):
			continue
		var mesh := _machine_composite_mesh(candidate.parts, key)
		var shadow: int = candidate.parts[0].shadow
		var layers: int = candidate.parts[0].layers
		var group_key := [mesh.get_instance_id(), 0, shadow, layers]
		if not static_groups.has(group_key):
			static_groups[group_key] = {"mesh": mesh, "material": null,
				"shadow": shadow, "layers": layers, "parts": [],
				"spatial_composite": true}
		for instance in candidate.instances:
			var sources: Array[MeshInstance3D] = []
			for part in instance.parts:
				if part.source not in sources:
					sources.append(part.source)
				skip_sources[part.source.get_instance_id()] = true
			static_groups[group_key].parts.append({"node": instance.anchor,
				"pose": instance.anchor.transform,
				"hide_nodes": sources})
	return skip_sources

func _batch_collector_cutters(dynamic_groups: Dictionary, skip_sources: Dictionary) -> void:
	var candidates := {}
	for anchor in machine_motion_anchors:
		if anchor.get_meta("machine_kind", "") != "collector":
			continue
		var parts: Array[Dictionary] = []
		var sources: Array[MeshInstance3D] = []
		var key: Array = ["collector_cutter"]
		var compatible := true
		for row in anchor.get_meta("motion_meshes", []):
			if row.role != "cutter":
				continue
			var source: MeshInstance3D = row.node
			if not is_instance_valid(source) or source.mesh == null or source.get_child_count() != 0 \
					or source.material_overlay != null or source.visibility_range_end > 0.0:
				compatible = false
				break
			sources.append(source)
			for surface in source.mesh.get_surface_count():
				var finish: Material = source.material_override
				if finish == null:
					finish = source.get_surface_override_material(surface)
				if finish == null:
					finish = source.mesh.surface_get_material(surface)
				if (finish is BaseMaterial3D and finish.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED) \
						or (source.mesh is ArrayMesh and source.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES):
					compatible = false
					break
				parts.append({"source": source, "mesh": source.mesh, "surface": surface,
					"finish": finish, "pose": row.rest, "shadow": source.cast_shadow,
					"layers": source.layers})
				key.append_array([source.mesh.get_instance_id(), surface,
					finish.get_instance_id() if finish != null else 0, row.rest])
			if not compatible:
				break
		if not compatible or sources.size() != 10 or parts.is_empty():
			continue
		var shadow: int = parts[0].shadow
		var layers: int = parts[0].layers
		for part in parts:
			if part.shadow != shadow or part.layers != layers:
				compatible = false
				break
		if not compatible:
			continue
		key.append_array([shadow, layers])
		if not candidates.has(key):
			candidates[key] = {"parts": parts, "instances": []}
		candidates[key].instances.append({"anchor": anchor, "sources": sources})
	for key in candidates:
		var candidate: Dictionary = candidates[key]
		if candidate.instances.size() < MACHINE_BATCH_THRESHOLD:
			continue
		var mesh := _machine_composite_mesh(candidate.parts, key)
		var group_key := [mesh.get_instance_id(), 0, candidate.parts[0].shadow,
			candidate.parts[0].layers, "collector_cutter"]
		dynamic_groups[group_key] = {"mesh": mesh, "material": null,
			"shadow": candidate.parts[0].shadow, "layers": candidate.parts[0].layers,
			"parts": []}
		for instance in candidate.instances:
			var anchor: Node3D = instance.anchor
			var angle: float = float(anchor.get_meta("cutter_angle", 0.0))
			dynamic_groups[group_key].parts.append({"node": anchor,
				"pose": anchor.transform * cutter_pose(anchor, angle),
				"hide_nodes": instance.sources, "cutter": true})
			for source in instance.sources:
				skip_sources[source.get_instance_id()] = true

func _batch_machine_visuals_walk(node: Node3D, pose: Transform3D,
		moving: Dictionary, static_groups: Dictionary, dynamic_groups: Dictionary,
		rotating := false, skip_sources: Dictionary = {}) -> void:
	if not node.visible:
		return
	var next_pose := pose * node.transform
	var in_rotor: bool = rotating or node.name == "WheelRotor"
	if node.name == "WheelRotor":
		var hidden_core: Array[MeshInstance3D] = []
		var combined := _wheel_rotor_batch_mesh(node, hidden_core)
		if combined != null:
			var bucket := Vector2i(floori(next_pose.origin.x / WHEEL_ROTOR_BATCH_CELL),
				floori(next_pose.origin.z / WHEEL_ROTOR_BATCH_CELL))
			var key := [combined.get_instance_id(), 0, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, 1, bucket]
			if not dynamic_groups.has(key):
				dynamic_groups[key] = {"mesh": combined, "material": null,
					"shadow": GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "layers": 1, "parts": []}
			dynamic_groups[key].parts.append({"node": node, "pose": next_pose,
				"parent_pose": pose, "hide_nodes": hidden_core})
			return
	if node is MeshInstance3D and not skip_sources.has(node.get_instance_id()) and node.mesh != null and node.name != "ConveyorLoop" \
			and node.visibility_range_end <= 0.0:
		var mesh_part := node as MeshInstance3D
		var material := mesh_part.material_override
		var overrides := mesh_part.material_overlay != null
		for surface in mesh_part.mesh.get_surface_count():
			var finish := mesh_part.get_surface_override_material(surface)
			if finish is BaseMaterial3D:
				overrides = overrides or finish.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		if material is BaseMaterial3D:
			overrides = overrides or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		if not overrides:
			var dynamic: bool = in_rotor or moving.has(node.get_instance_id())
			var groups: Dictionary = dynamic_groups if dynamic else static_groups
			var batch_mesh: Mesh = _machine_batch_surface_mesh(mesh_part)
			var key := [batch_mesh.get_instance_id(), material.get_instance_id() if material != null else 0,
				mesh_part.cast_shadow, mesh_part.layers]
			if not groups.has(key):
				groups[key] = {"mesh": batch_mesh, "material": material,
					"shadow": mesh_part.cast_shadow, "layers": mesh_part.layers, "parts": []}
			groups[key].parts.append({"node": mesh_part, "pose": next_pose})
	for child in node.get_children():
		if child is Node3D:
			_batch_machine_visuals_walk(child, next_pose, moving, static_groups, dynamic_groups,
				in_rotor, skip_sources)

func _emit_machine_mesh_batches(groups: Dictionary, batches: Node3D, dynamic: bool,
		force_live: bool = false) -> void:
	var batch_index := batches.get_child_count()
	if not dynamic and force_live:
		var merged_by_layer := {}
		for group in groups.values():
			if group.parts.is_empty():
				continue
			var layer_key := [group.shadow, group.layers]
			if not merged_by_layer.has(layer_key):
				merged_by_layer[layer_key] = {"shadow": group.shadow, "layers": group.layers, "finishes": {}}
			var finishes: Dictionary = merged_by_layer[layer_key].finishes
			var mesh: Mesh = group.mesh
			for part in group.parts:
				if part.has("hide_nodes"):
					for source in part.hide_nodes:
						source.visible = false
				else:
					part.node.visible = false
				for s in mesh.get_surface_count():
					var finish: Material = group.material if group.material != null else mesh.surface_get_material(s)
					var finish_id := finish.get_instance_id() if finish != null else 0
					if not finishes.has(finish_id):
						var st := SurfaceTool.new()
						st.begin(Mesh.PRIMITIVE_TRIANGLES)
						st.set_material(finish)
						finishes[finish_id] = st
					(finishes[finish_id] as SurfaceTool).append_from(mesh, s, part.pose)
		for layer_group in merged_by_layer.values():
			var merged_mesh: ArrayMesh
			for st: SurfaceTool in layer_group.finishes.values():
				merged_mesh = st.commit(merged_mesh)
			if merged_mesh == null:
				continue
			merged_mesh = finish_mesh(merged_mesh, true)
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = merged_mesh
			multi.instance_count = 1
			multi.set_instance_transform(0, Transform3D.IDENTITY)
			multi.custom_aabb = merged_mesh.get_aabb()
			var instance := MultiMeshInstance3D.new()
			instance.name = "MachineBatch%d" % batch_index
			instance.multimesh = multi
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.layers = layer_group.layers
			instance.set_meta("spatial_composite", true)
			batches.add_child(instance)
			batch_index += 1
		return
	for group in groups.values():
		if group.parts.size() < (1 if force_live else 2):
			continue
		var partitions: Array = [group.parts]
		# Smaller fields submit more cell batches than culling saves. Count only
		# eligible static machines so wheels and foundations cannot trigger it.
		if not dynamic and group.get("spatial_composite", false) \
				and machine_static_spatial_tiles > 0 \
				and machine_batch_static_machine_count >= MACHINE_STATIC_SPATIAL_FIELD_THRESHOLD \
				and group.parts.size() >= MACHINE_STATIC_SPATIAL_THRESHOLD:
			var cells := {}
			var cell_size := PITCH * float(machine_static_spatial_tiles)
			for part in group.parts:
				var at: Vector3 = part.pose.origin
				var cell := Vector2i(floori(at.x / cell_size), floori(at.z / cell_size))
				if not cells.has(cell):
					cells[cell] = []
				cells[cell].append(part)
			partitions = cells.values()
		for parts in partitions:
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = group.mesh
			multi.instance_count = parts.size()
			var bounds: AABB = parts[0].pose * group.mesh.get_aabb()
			var motion_margin := bounds.size.length()
			for index in parts.size():
				multi.set_instance_transform(index, parts[index].pose)
				var part_bounds: AABB = parts[index].pose * group.mesh.get_aabb()
				bounds = bounds.merge(part_bounds)
				motion_margin = maxf(motion_margin, part_bounds.size.length())
				if parts[index].has("hide_nodes"):
					for source in parts[index].hide_nodes:
						source.visible = false
				else:
					parts[index].node.visible = false
			multi.custom_aabb = bounds.grow(maxf(6.0, motion_margin)) if dynamic else bounds
			var instance := MultiMeshInstance3D.new()
			instance.name = "MachineBatch%d" % batch_index
			instance.multimesh = multi
			instance.material_override = group.material
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if force_live else group.shadow
			instance.layers = group.layers
			instance.set_meta("spatial_composite", group.get("spatial_composite", false))
			batches.add_child(instance)
			if dynamic:
				var rotor_only := true
				var cutter_only := true
				for part in parts:
					rotor_only = rotor_only and part.node.name == "WheelRotor"
					cutter_only = cutter_only and part.get("cutter", false)
				machine_dynamic_batches.append({"mesh": multi, "parts": parts,
					"rotor_only": rotor_only, "cutter_only": cutter_only})
				for index in parts.size():
					var part: Dictionary = parts[index]
					if part.get("cutter", false):
						machine_cutter_batch_slots[part.node.get_instance_id()] = {"mesh": multi, "index": index}
					if part.node.name == "WheelRotor":
						var node_id: int = part.node.get_instance_id()
						machine_batched_rotors[node_id] = true
						machine_batched_rotor_slots[node_id] = {"mesh": multi, "index": index,
							"node": part.node, "parent_pose": part.parent_pose}
			batch_index += 1

func update(visible_rotors_only := false) -> void:
	if machine_dynamic_batches.is_empty():
		return
	var to_local := machine_root.global_transform.affine_inverse()
	if visible_rotors_only:
		for node_id in wheel_updated_rotors:
			var slot: Dictionary = machine_batched_rotor_slots.get(node_id, {})
			if slot.is_empty():
				continue
			var pose: Transform3D = slot.parent_pose * (wheel_batch_poses[node_id] \
				if wheel_batch_poses.has(node_id) else slot.node.transform)
			slot.mesh.set_instance_transform(slot.index, pose)
	for group in machine_dynamic_batches:
		if visible_rotors_only and (group.rotor_only or group.get("cutter_only", false)):
			continue
		var mesh: MultiMesh = group.mesh
		for index in group.parts.size():
			var part: Dictionary = group.parts[index]
			if visible_rotors_only and machine_batched_rotor_slots.has(part.node.get_instance_id()):
				continue
			# Wheel ancestors remain fixed until the next topology rebuild. Keep
			# their machine-root-relative pose and update only the moving rotor.
			var motion_pose: Transform3D
			if part.has("parent_pose"):
				var node_id: int = part.node.get_instance_id()
				# An offscreen rotor keeps its last instance pose until it returns.
				if visible_rotors_only and not wheel_updated_rotors.has(node_id):
					continue
				motion_pose = part.parent_pose * (wheel_batch_poses[node_id] \
					if wheel_batch_poses.has(node_id) else part.node.transform)
			else:
				motion_pose = to_local * part.node.global_transform
			mesh.set_instance_transform(index, motion_pose)
func _batch_conveyor_loops(batches: Node3D) -> void:
	var loops: Array[MeshInstance3D] = []
	for part in machine_root.find_children("ConveyorLoop", "MeshInstance3D", true, false):
		if part.is_visible_in_tree() and part.mesh != null and part.material_override is StandardMaterial3D:
			loops.append(part)
	if loops.size() < MACHINE_BATCH_THRESHOLD:
		return
	for loop in loops:
		if loop.mesh != loops[0].mesh or loop.cast_shadow != loops[0].cast_shadow or loop.layers != loops[0].layers:
			return
	var finish := ProductionConveyorArt.multimesh_material()
	if finish == null:
		return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	multi.mesh = loops[0].mesh
	multi.instance_count = loops.size()
	var to_local := machine_root.global_transform.affine_inverse()
	var bounds: AABB = to_local * loops[0].global_transform * loops[0].mesh.get_aabb()
	for index in loops.size():
		var loop := loops[index]
		var pose: Transform3D = to_local * loop.global_transform
		multi.set_instance_transform(index, pose)
		multi.set_instance_custom_data(index, Color(loop.material_override.uv1_offset.x, 0, 0))
		bounds = bounds.merge(pose * loop.mesh.get_aabb())
		loop.visible = false
	multi.custom_aabb = bounds
	var instance := MultiMeshInstance3D.new()
	instance.name = "ConveyorLoopBatch"
	instance.multimesh = multi
	instance.material_override = finish
	instance.cast_shadow = loops[0].cast_shadow
	instance.layers = loops[0].layers
	batches.add_child(instance)
	machine_conveyor_batches.append({"mesh": multi, "parts": loops})
	for index in loops.size():
		machine_conveyor_batch_slots[loops[index].get_instance_id()] = {"mesh": multi, "index": index}

func rebuild(root: Node3D, motion_anchors: Array[Node3D], enabled: bool,
		force_live: bool = false) -> void:
	machine_root = root
	machine_motion_anchors = motion_anchors
	machine_dynamic_batches.clear()
	machine_conveyor_batches.clear()
	machine_conveyor_batch_slots.clear()
	machine_batch_static_machine_count = 0
	machine_batched_rotors.clear()
	machine_batched_rotor_slots.clear()
	machine_cutter_batch_slots.clear()
	wheel_batch_poses.clear()
	wheel_updated_rotors.clear()
	if not enabled or (not force_live and machine_root.get_child_count() < MACHINE_BATCH_THRESHOLD):
		return
	var moving := {}
	for anchor in machine_root.get_children():
		if anchor.get_meta("machine_kind", "") in ["collector", "belt", "processor"]:
			machine_batch_static_machine_count += 1
		for row in anchor.get_meta("motion_meshes", []):
			moving[row.node.get_instance_id()] = true
	var static_groups := {}
	var dynamic_groups := {}
	var skip_sources := {} if force_live else _batch_machine_composites(moving, static_groups, false)
	_batch_collector_cutters(dynamic_groups, skip_sources)
	for anchor in machine_root.get_children():
		if anchor is Node3D:
			_batch_machine_visuals_walk(anchor, Transform3D.IDENTITY, moving, static_groups,
				dynamic_groups, false, skip_sources)
	var batches := Node3D.new()
	batches.name = "MachineVisualBatches"
	machine_root.add_child(batches)
	_emit_machine_mesh_batches(static_groups, batches, false, force_live)
	_emit_machine_mesh_batches(dynamic_groups, batches, true, force_live)
	_batch_conveyor_loops(batches)
