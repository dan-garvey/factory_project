extends SceneTree
## Isolated asset controls; no game state, native body or desktop operation.
const Opening = preload("res://opening/opening.gd")
const Visuals = Opening.ProductionVisuals
var checks := 0
var failed := false
var error_count := 0
var tangent_max_dot := 0.0
var tangent_min_length := 1.0
const EPSILON := 0.00001
# ArrayMesh readback decodes 16-bit octahedral normals/tangents, even without
# compressed positions. This is a render-attribute allowance, never build reach.
const TANGENT_EPSILON := 0.0002

func valid_tangent(tangent: Vector3, normal: Vector3) -> bool:
	return tangent.is_finite() and tangent.length() > 0.99 and absf(tangent.dot(normal)) < TANGENT_EPSILON

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		error_count += 1
		if error_count <= 8:
			push_error(message)

func vertex_key(point: Vector3) -> String:
	return "%d,%d,%d" % [roundi(point.x * 1000000), roundi(point.y * 1000000), roundi(point.z * 1000000)]

func check_box(dimensions: Vector3) -> void:
	var mesh := Visuals.box_mesh(dimensions)
	verify(mesh == Visuals.box_mesh(dimensions), "Repeated parts reuse the authored mesh resource.")
	verify(mesh.get_aabb().size.is_equal_approx(dimensions), "Chamfers preserve the exact original part envelope.")
	var data := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = data[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = data[Mesh.ARRAY_TEX_UV]
	var tangents: PackedFloat32Array = data[Mesh.ARRAY_TANGENT]
	verify(vertices.size() == 132 and normals.size() == vertices.size(), "Every closed chamfered box has 44 complete triangles.")
	verify(uv.size() == vertices.size() and tangents.size() == vertices.size() * 4,
		"Every surface has actual UVs and normal-map tangents.")
	var edges: Dictionary = {}
	var volume := 0.0
	for index in range(0, vertices.size(), 3):
		var a := vertices[index]
		var b := vertices[index + 1]
		var c := vertices[index + 2]
		var winding := (b - a).cross(c - a)
		verify(winding.length_squared() > 0.000000000001, "A chamfer has no collapsed triangle.")
		verify(winding.dot(normals[index]) < 0, "Every front face uses Godot's clockwise winding and an outward normal.")
		volume += a.dot(b.cross(c)) / 6.0
		for pair in [[a, b], [b, c], [c, a]]:
			var first := vertex_key(pair[0])
			var second := vertex_key(pair[1])
			var key := first + "/" + second if first < second else second + "/" + first
			edges[key] = int(edges.get(key, 0)) + 1
	for count in edges.values():
		verify(count == 2, "Every geometric edge has two faces; chamfer corners cannot leave holes.")
	var full_volume := dimensions.x * dimensions.y * dimensions.z
	verify(absf(volume) > full_volume * 0.8 and absf(volume) < full_volume,
		"The asset is a solid box with cut shoulders, rather than missing or overlapping faces.")
	for index in range(vertices.size()):
		var normal := normals[index]
		var tangent := Vector3(tangents[index * 4], tangents[index * 4 + 1], tangents[index * 4 + 2])
		tangent_max_dot = maxf(tangent_max_dot, absf(tangent.dot(normal)))
		tangent_min_length = minf(tangent_min_length, tangent.length())
		if not valid_tangent(tangent, normal) and error_count == 0:
			print(JSON.stringify({"first_normal": str(normal), "first_tangent": str(tangent),
				"dot": tangent.dot(normal), "length": tangent.length()}))
		verify(normal.is_finite() and is_equal_approx(normal.length(), 1.0), "Asset normals are finite unit vectors.")
		verify(valid_tangent(tangent, normal),
			"Normal-map tangents are finite and perpendicular to the actual face.")
		verify(uv[index].is_finite(), "Texture coordinates remain finite on thin machine details.")

func _initialize() -> void:
	verify(not valid_tangent(Vector3.ZERO, Vector3.UP), "Missing tangents cannot pass the packed-attribute allowance.")
	verify(not valid_tangent(Vector3(1, 0.01, 0).normalized(), Vector3.UP), "A misoriented tangent still fails.")
	verify(not valid_tangent(Vector3(INF, 0, 0), Vector3.UP), "Non-finite tangents still fail.")
	for dimensions in [Vector3(1.25, 0.1, 0.67), Vector3(0.12, 1.1, 0.14),
		Vector3(0.56, 0.17, 0.55), Vector3(0.035, 0.035, 0.035), Vector3(1.615, 0.12, 1.615)]:
		check_box(dimensions)
	verify(Visuals.box_mesh(Vector3(1, 1, 1)) != Visuals.box_mesh(Vector3(1, 1, 1.01)),
		"Different part sizes cannot alias one cached mesh.")
	var paint := Visuals.material(Color("d6a34d"), 0.08, 0.5)
	var steel := Visuals.material(Color("a6b4af"), 0.85, 0.4)
	verify(paint == Visuals.material(Color("d6a34d"), 0.08, 0.5) and paint != steel,
		"Shared finishes reuse resources without mixing paint and machined steel.")
	verify(paint.normal_enabled and paint.normal_texture != null and paint.roughness_texture != null,
		"The actual material binds surface normals and roughness variation.")
	verify(paint.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL and paint.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,
		"Production surfaces keep lit, opaque material response.")
	verify(paint.normal_texture.seamless and paint.normal_texture.generate_mipmaps
		and paint.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC,
		"Microdetail repeats without an unmipmapped distant texture path.")
	var view := Opening.new()
	var parent := Node3D.new()
	var part: MeshInstance3D = view._machine_box(parent, "FixtureHousing", Vector3(1, 2, 3), Vector3(0.56, 0.17, 0.55), Color("d6a34d"))
	verify(part.mesh is ArrayMesh and part.material_override == paint and part.position == Vector3(1, 2, 3),
		"The ordinary machine helper actually consumes the production geometry and shared finish.")
	var cylinder: MeshInstance3D = view._machine_cylinder(parent, "FixtureBearing", Vector3.ZERO, 0.1, 0.2, Color("a6b4af"))
	verify(cylinder.mesh is CylinderMesh and cylinder.mesh.radial_segments == 48 and cylinder.material_override == steel,
		"Actual bearing helpers consume the smoother geometry and machined finish.")
	verify(view.model == null and parent.get_child_count() == 2 and part.get_child_count() == 0 and cylinder.get_child_count() == 0,
		"Asset creation introduces no authority, physics body or child controller.")
	parent.free()
	view.machine_root = Node3D.new()
	view.state = {"options": {"native": true}, "entities": {"fixture": {"kind": "collector", "cell": [0, 0], "axis": 1}}, "links": [], "drive_links": []}
	var before: Dictionary = view.state.duplicate(true)
	view._rebuild_machines()
	var collector: Node3D = view.machine_root.get_child(0)
	verify(is_equal_approx(collector.get_node("StockBed").material_override.metallic, 0.85),
		"The actual collector's working bed uses exposed steel.")
	var lower_housing := collector.get_node_or_null("CollectorCastFrame/CastLowerHousing") as MeshInstance3D
	var cast_finish := lower_housing.material_override as StandardMaterial3D if lower_housing != null else null
	verify(cast_finish != null and cast_finish == Opening.ProductionCollectorArt.coating(
		Opening.COLORS.collector.darkened(0.09)) and cast_finish.metallic < 0.1
		and cast_finish.roughness_texture != null,
		"The actual collector casting keeps its distinct painted source finish.")
	verify(view.state == before and view.model == null, "Surface presentation cannot mutate the machine projection.")
	view.machine_root.free()
	view.free()
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
		"error_count": error_count, "tangent_max_dot": tangent_max_dot, "tangent_min_length": tangent_min_length,
		"scope": "closed chamfer geometry, tangents, shared PBR resources and actual machine helper integration",
		"rendered_quality": "not_assessed", "desktop": "not_used"}))
	quit(1 if failed else 0)
