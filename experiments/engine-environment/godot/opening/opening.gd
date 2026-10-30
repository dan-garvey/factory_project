extends Node3D
const Widgets = preload("res://opening/production_widgets.gd")
## Input and presentation only. The native model owns ordinary material and build mutations.

const NativeWorldModel = preload("res://opening/native_model.gd")
const RecoveryActions = preload("res://opening/recovery_actions.gd")
const Store = preload("res://save-tests/checkpoint_file.gd")
const ActorWorld = preload("res://opening/actor_world.gd")
const CharacterPresenter = preload("res://opening/character_presenter.gd")
const Geometry = preload("res://opening/site_geometry.gd")
const BuildingHotbar = preload("res://opening/building_hotbar.gd")
const ArrivalRevealAudio = preload("res://opening/arrival_reveal_audio.gd")
const ConstructionAudio = preload("res://opening/construction_audio.gd")
const MechanicalAmbience = preload("res://opening/mechanical_ambience.gd")
const ProductionInterface = preload("res://opening/production_interface.gd")

const ProductionCoating = preload("res://opening/production_surfaces.gd").ProductionCoating
const ProductionCollectorArt = preload("res://opening/production_collectors.gd").ProductionCollectorArt
const ProductionCollectorFeedArt = preload("res://opening/production_collectors.gd").ProductionCollectorFeedArt
const ProductionCollectorOutputArt = preload("res://opening/production_collectors.gd").ProductionCollectorOutputArt
const ProductionCollectorServiceArt = preload("res://opening/production_collectors.gd").ProductionCollectorServiceArt
const ProductionCollectorToolingArt = preload("res://opening/production_collectors.gd").ProductionCollectorToolingArt
const ProductionConveyorArt = preload("res://opening/production_conveyors.gd").ProductionConveyorArt
const ProductionConveyorFrameArt = preload("res://opening/production_conveyors.gd").ProductionConveyorFrameArt
const ProductionConveyorHubArt = preload("res://opening/production_conveyors.gd").ProductionConveyorHubArt
const ProductionDriveJournalArt = preload("res://opening/production_presses.gd").ProductionDriveJournalArt
const ProductionEnvironment = preload("res://opening/production_environment.gd").ProductionEnvironment
const ProductionFeedSleeveArt = preload("res://opening/production_collectors.gd").ProductionFeedSleeveArt
const ProductionFoundationArt = preload("res://opening/production_foundations.gd").ProductionFoundationArt
const ProductionPaddleArt = preload("res://opening/production_waterwheels.gd").ProductionPaddleArt
const ProductionPressArt = preload("res://opening/production_presses.gd").ProductionPressArt
const ProductionPressCrownArt = preload("res://opening/production_presses.gd").ProductionPressCrownArt
const ProductionPressDieArt = preload("res://opening/production_presses.gd").ProductionPressDieArt
const ProductionPressRearFrameArt = preload("res://opening/production_presses.gd").ProductionPressRearFrameArt
const ProductionPressTrayArt = preload("res://opening/production_presses.gd").ProductionPressTrayArt
const ProductionSkidArt = preload("res://opening/production_foundations.gd").ProductionSkidArt
const ProductionTransmissionFinish = preload("res://opening/production_surfaces.gd").ProductionTransmissionFinish
const ProductionVisuals = preload("res://opening/production_surfaces.gd").ProductionVisuals
const ProductionWheelArt = preload("res://opening/production_waterwheels.gd").ProductionWheelArt
const ProductionWheelPierArt = preload("res://opening/production_waterwheels.gd").ProductionWheelPierArt
const ProductionWheelSupportArt = preload("res://opening/production_waterwheels.gd").ProductionWheelSupportArt

const MachineBatcher = preload("res://opening/machine_batches.gd")
var machine_batches := MachineBatcher.new()

const STEP_SECONDS := 0.45
const PITCH := Geometry.PITCH
const NAMES := {"collector": "Collector", "belt": "Belt", "processor": "Press", "wheel": "Waterwheel", "foundation": "Foundation", "pod_workshop": "Pod workshop"}
const COLORS := {"collector": Color("96805c"), "belt": Color("538e88"), "processor": Color("bd7054"), "wheel": Color("8b9caa")}

var model
var actor_world
var character_presenter
var actor_label: Label
var startup_save_pending := false
var startup_save_scheduled := false
var auto_advance := true
var client := "P"
var request_sequence := 0
# A fresh view must not restart request IDs into a restored authority's cache.
# This nonce identifies submitted intents; it never randomizes simulation rules.
var request_namespace := "opening-" + Crypto.new().generate_random_bytes(16).hex_encode() + "-"
var save_slot := ""
var save_slot_ready := false
var save_slot_owned := false
var last_save_result: Dictionary = {}
var last_load_result: Dictionary = {}
var startup_resume_checkpoint: Dictionary = {}
const FIRST_COLLECTOR_HINT := "Choose Collector [1] on the ore-bearing ground."
var mode := "inspect"
var pending_link := ""
var selected := ""
var explanation_open := false
var help_close_button: Button
var elapsed := 0.0
var orbit_yaw := 0.68
var orbit_pitch := 0.82
var native_camera_initialized := false
var distance := 18.5
var focus := Vector3(1.3, 0.0, 1.1)
const FIRST_PERSON_EYE_OFFSET := 0.35
const FIRST_PERSON_BLEND_DISTANCE := 4.0
var hover_cell := Vector2i(99, 99)
var visual_revision := -1
var geometry_key := ""
var item_visual_key: Array = []
var ui_refresh_key: Array = []
var hand_tree_nodes: Dictionary = {}
var ore_field_visual: Node3D
var ore_field_visual_key := ""
var hand_tree_assets: Dictionary = {}
var mature_tree_nodes: Dictionary = {}
var mature_tree_collision_rows: Dictionary = {}
var camera: Camera3D
var machine_root: Node3D
var item_root: Node3D
var workpiece_item_assets
var hover: MeshInstance3D
var selection_ring: MeshInstance3D
var machine_preview: Node3D
var component_preview: Node3D
var press_snap_target: MeshInstance3D
var press_snap_material: StandardMaterial3D
var press_snap_lift: Node3D
var press_snap_lift_tip: MeshInstance3D
var press_snap_lift_material: StandardMaterial3D
var component_preview_kind := ""
var component_preview_pose_key := ""
var component_preview_material: StandardMaterial3D
var component_preview_blocked := false
var component_preview_snap := ""
var mutable_machine_preview: Node3D
var machine_preview_key := ""
var machine_preview_material: StandardMaterial3D
var belt_preview_material: StandardMaterial3D
var packed_preview_templates: Dictionary = {}
var packed_preview_nodes: Dictionary = {}
var preview_variant_pending := false
var preview_prefetch_paths: Array[String] = []
var preview_prefetch_complete := false
const BAKED_WHEEL_PREVIEW_MAX_TILES := 9
var machine_rotors: Array[Dictionary] = []
var machine_rotor_cells: Array[Dictionary] = []
var machine_motion_anchors: Array[Node3D] = []
# Spatial draws help the measured native Windows renderer at large scale,
# but overwhelm the WSL Compatibility path even when they cull triangles.
var transmission_preview_point: Array = []
var wheel_rotor: Node3D
var machine_body_context := ""
var machine_press_poses: Dictionary = {}
var status_label: Label
var developer_mode_label: Label
var fps_label: Label
var fps_elapsed := 0.0
var status_footer: Control
var status_refused := false
var footer_snapshot_ready := false
var footer_fit_pending := false
var pointed_summary_cache_key: Array = []
var stock_label: Label
var parts_label: Label
var goal_text := ""
var goal_detail := ""
var objective_title := "FIRST SHIFT  /  01"
var manager_log_layer: CanvasLayer
var manager_log_panel: PanelContainer
var manager_log_current: Label
var manager_log_completion_entry: Label
var manager_log_projects: VBoxContainer
var manager_log_open := false
var workshop_completion_observed: Variant = null
var workshop_completion_audio: AudioStreamPlayer
var workshop_completion_cue_count := 0
var power_label: Label
var inspector: Label
var inspector_title: Label
var inspection_actions: HBoxContainer
var pointed_summary: PanelContainer
var pointed_name: Label
var pointed_detail: Label
var object_menu: PopupPanel
var object_menu_scrim: ColorRect
var object_menu_title: Label
var object_menu_operations_label: Label
var object_menu_close: Button
var object_menu_operations: VBoxContainer
var object_menu_detail_panel: PanelContainer
var object_menu_desired_extent := Vector2i(500, 400)
var object_menu_viewport_size := Vector2i.ZERO
var object_menu_target := ""
var object_menu_closed_frame := -1
var mouse_capture_owned := false
var mouse_capture_skip_motion := false
var pause_menu: PanelContainer
var pause_menu_scrim: ColorRect
var pause_resume_button: Button
var pause_exit_button: Button
var pause_exit_confirmation: ConfirmationDialog
var recovery_actions
var loose_material_controls
var developer_material_tools := "--debug-material-tools" in OS.get_cmdline_user_args()
var transmission_controls
var transmission_presenter
var construction_audio
var engineering_presenter
var mechanical_ambience
var retrieve_button: Button
var remove_button: Button
var save_button: Button
var load_button: Button
var help_panel: PanelContainer
var help_title: Label
var help_body: Label
var tool_buttons: Dictionary = {}
var building_hotbar
var foundation_level := Geometry.HEIGHT_DENOMINATOR
var foundation_steps := false
var foundation_steps_toggle: CheckButton
var foundation_area_mode := false
var foundation_area_started := false
var foundation_area_start := Vector2i.ZERO
var foundation_area_toggle: CheckButton
var foundation_level_controls: HBoxContainer
var foundation_level_label: Label
var wheel_level := 4
var wheel_tiles := 3
var wheel_size_controls: HBoxContainer
var wheel_size_label: Label
var state: Dictionary = {}
var consumed_shortcut_keys: Dictionary = {}
var held_crank := ""
var held_crank_seconds := 0.0
var held_crank_context := ""
var held_crank_request := ""
var catalog_button: Button
var controls_label: Label
var building_rotation := 0
var rotation_button: Button
var placement_options_panel: PanelContainer
var placement_options_column: VBoxContainer
var placement_options_title: Label
var placement_options_hint: Label
var placement_options_axis: Button
var placement_cell_cache := Vector2i.ZERO
var arrival_assembly_controls
var arrival_assembly_scroll: ScrollContainer
var component_nudge_active := false
var component_nudge_center: Array = []
var landing_pod_visual: Node3D
var landing_hub_visual: Node3D
var landing_pod_batch_visual: MeshInstance3D
var landing_hub_batch_visual: MeshInstance3D
var landing_hub_pick: StaticBody3D
var arrival_reveal_probe := false
var arrival_reveal_active := false
var arrival_reveal_elapsed := 0.0
var arrival_reveal_pod_anchor := Vector3.ZERO
var arrival_gameplay_canvas: CanvasLayer
var arrival_reveal_canvas: CanvasLayer
var arrival_reveal_caption: Label
var arrival_reveal_audio
const ARRIVAL_REVEAL_SECONDS := 2.8

static func apply_test_window_title(tree: SceneTree) -> bool:
	var purpose := ""
	var found := false
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--test-purpose="):
			continue
		if found:
			push_error("Use exactly one test window purpose")
			tree.quit(2)
			return false
		found = true
		purpose = argument.trim_prefix("--test-purpose=")
	if not found:
		return true
	if purpose.strip_edges().is_empty() or purpose.length() > 60 or "\n" in purpose or "\r" in purpose:
		push_error("Invalid test window purpose")
		tree.quit(2)
		return false
	tree.root.title = "Factory — " + purpose
	return true

func _ready() -> void:
	if not apply_test_window_title(get_tree()):
		return
	if model == null:
		push_error("Opening requires an assigned native or shared model")
		get_tree().quit(1)
		return
	if save_slot.is_empty():
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--save-slot="):
				configure_save_slot(argument.trim_prefix("--save-slot="))
	_build_world()
	_build_interface()
	for menu: Node in [object_menu, pause_menu, pause_exit_confirmation,
			building_hotbar.catalog, manager_log_layer, help_panel]:
		if menu != null:
			menu.connect("visibility_changed", _on_mouse_menu_visibility_changed)
	_refresh()
	if _native_transmission():
		if state.has("hand_sources"):
			call_deferred("_warm_packed_machine_previews")
		else:
			_prime_machine_visuals()
	if not _native_transmission():
		_message("WASD walks. Build nearby; a wheel in the stream drives connected parts.")
	elif not state.has("hand_sources"):
		_message(FIRST_COLLECTOR_HINT)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--resume-input="):
			var result: Dictionary = _load_worksite(argument.trim_prefix("--resume-input="), true)
			if not result.accepted or not model.projection().options.get("opening", false):
				push_error("Opening resume refused; no fresh-world fallback")
				get_tree().quit(1)
				return
			startup_resume_checkpoint = model.checkpoint()
			startup_save_pending = true
			_message("Worksite reopened in this session. Your original save is kept.")
	if not _start_character_world():
		return
	_start_character_presenter()
	if model is NativeWorldModel and state.has("landing_pod") and startup_resume_checkpoint.is_empty() \
			and (auto_advance or arrival_reveal_probe):
		_maybe_start_arrival_reveal.call_deferred()

func _start_character_world() -> bool:
	actor_world = ActorWorld.new()
	actor_world.name = "OpeningActors"
	actor_world.set_belt_step_seconds(STEP_SECONDS if auto_advance else 0.0)
	actor_world.pose_published.connect(_actor_pose)
	actor_world.initialization_failed.connect(_actor_failed)
	var configured: Dictionary = actor_world.configure(model)
	if not configured.accepted:
		actor_world.free()
		actor_world = null
		_actor_failed(client, configured.reason)
		return false
	add_child(actor_world)
	for actor in model.projection().actors:
		if not actor_world.ensure_actor(actor).accepted:
			return false
	return true

func _start_character_presenter() -> void:
	distance = 14.0
	character_presenter = CharacterPresenter.new()
	character_presenter.name = "Characters"
	character_presenter.configure(self)
	add_child(character_presenter)

func _actor_pose(actor: String, sample: Dictionary) -> void:
	var result: Dictionary = model.publish_actor(actor, sample.position, sample.native_epoch)
	if not result.accepted:
		_actor_failed(actor, result.reason)
		return
	if character_presenter != null:
		character_presenter.observe_native_sample(actor, sample)
	# The ordinary render-frame refresh follows this physics cut. The first
	# ready pose and paused fixtures still need their immediate snapshot.
	if not (model is NativeWorldModel and auto_advance \
			and state.get("actors", {}).get(actor, {}).get("ready", false)):
		_refresh()
	if startup_save_pending and not startup_save_scheduled:
		var all_ready := true
		for current in model.projection().actors.values():
			all_ready = all_ready and current.ready
		if all_ready:
			startup_save_scheduled = true
			call_deferred("_finish_startup_save")

func _finish_startup_save() -> void:
	var saved: Dictionary = _save_worksite()
	if not saved.accepted:
		_actor_failed(client, "resume_save_failed:" + str(saved.reason))
		return
	startup_save_pending = false
	_refresh_ui()
	_message("Worksite reopened in this session. Your original save is kept.")

func _actor_failed(actor: String, reason: String) -> void:
	if model != null and model.has_method("invalidate_actor"):
		model.invalidate_actor(actor)
	push_error("Physical character unavailable for " + actor + ": " + reason)
	get_tree().quit(1)

func _can_control_character() -> bool:
	return _actor_ready_for_actions() and not _object_menu_open() and not _pause_menu_open() \
		and DisplayServer.window_get_active_popup() == DisplayServer.INVALID_WINDOW_ID

func _actor_ready_for_actions() -> bool:
	return not arrival_reveal_active and not manager_log_open and not _catalog_open() and not explanation_open \
		and not startup_save_pending and state.get("actors", {}).get(client, {}).get("ready", false)

func _can_use_object_actions() -> bool:
	return _actor_ready_for_actions()

func _can_choose_tool() -> bool:
	# The catalog holds movement while keeping its own choices available.
	return not arrival_reveal_active and not manager_log_open and not explanation_open and not startup_save_pending and not _object_menu_open() and not _pause_menu_open() \
		and state.get("actors", {}).get(client, {}).get("ready", false)

func _native_transmission() -> bool:
	return state.get("options", {}).get("native", false)

func _can_present_confirmed_motion() -> bool:
	return _native_transmission() and not explanation_open and not startup_save_pending and state.get("actors", {}).get(client, {}).get("ready", false)

func _contains_target(snapshot: Dictionary, id: String) -> bool:
	return snapshot.get("entities", {}).has(id) or snapshot.get("foundations", {}).has(id) or (snapshot.get("options", {}).get("native", false)
		and (snapshot.get("transmission_parts", {}).has(id) or snapshot.get("belt_spans", {}).has(id)
			or snapshot.get("placed_components", {}).has(id)
			or (snapshot.get("fabrication_hub", {}).get("installed", false)
				and snapshot.fabrication_hub.get("id", "") == id)))

func _refresh_transmission() -> void:
	if not _native_transmission():
		if transmission_controls != null:
			if not transmission_controls.active_tool.is_empty():
				transmission_controls.cancel()
				mode = "inspect"
			transmission_controls.refresh()
		if transmission_presenter != null:
			transmission_presenter.refresh()
		return
	if transmission_controls == null:
		# Historical fixed-roster runtimes do not include the native helpers.
		# A native worksite requires the complete captured native project.
		var controls_path := "res://opening/native_transmission_controls.gd"
		var presenter_path := "res://opening/native_transmission_presenter.gd"
		if not ResourceLoader.exists(controls_path, "Script") or not ResourceLoader.exists(presenter_path, "Script"):
			push_error("Native transmission requires the complete captured project")
			get_tree().quit(1)
			return
		transmission_controls = load(controls_path).new()
		transmission_controls.custom_minimum_size.y = 37
		placement_options_column.add_child(transmission_controls)
		transmission_controls.configure(self)
		transmission_presenter = load(presenter_path).new()
		add_child(transmission_presenter)
		transmission_presenter.configure(self)
	transmission_controls.refresh()
	transmission_presenter.refresh()
	var active: bool = not transmission_controls.active_tool.is_empty()
	transmission_controls.visible = active
	if not active and mode in ["gear", "drive", "belt", "gearbox", "vertical_gearbox", "chain_drive"]:
		mode = "inspect"
	_update_cursor()

func _engineering_progress() -> Dictionary:
	if not _native_transmission():
		return {}
	var records: Variant = state.get("opening_engineering", {})
	if not records is Dictionary:
		return {}
	var report: Variant = records.get(client, {})
	if not report is Dictionary or report.get("schema") != 1 or report.get("format") != "factory-opening-engineering" or report.get("actor") != client or report.get("known_actor") != true:
		return {}
	var cell: Variant = report.get("wheel_cell")
	if not cell is Array or cell.size() != 2 or typeof(cell[0]) != TYPE_INT or typeof(cell[1]) != TYPE_INT:
		return {}
	if typeof(report.get("products")) != TYPE_INT or typeof(report.get("target")) != TYPE_INT or not report.get("phase", "") in ["first_shift", "move_source", "restore_drive", "deliver_more", "ready"]:
		return {}
	return report

func _refresh_engineering(snapshot_ready: bool) -> void:
	var report := _engineering_progress() if snapshot_ready else {}
	if report.is_empty():
		if engineering_presenter != null:
			engineering_presenter.visible = false
		goal_detail = ""
		return
	if engineering_presenter == null:
		var path := "res://opening/upstream_drive_challenge.gd"
		if not ResourceLoader.exists(path, "Script"):
			push_error("Native engineering content requires the complete captured project")
			get_tree().quit(1)
			return
		engineering_presenter = load(path).new()
		add_child(engineering_presenter)
		engineering_presenter.configure(self, Vector2i(report.wheel_cell[0], report.wheel_cell[1]))
	var cell := Vector2i(report.wheel_cell[0], report.wheel_cell[1])
	if engineering_presenter.target_wheel_cell != cell:
		engineering_presenter.set_target_wheel_cell(cell)
	engineering_presenter.refresh()
	# Challenge eligibility and progress come from the native projection.
	var active: bool = report.phase != "first_shift"
	engineering_presenter.visible = active
	if not active:
		goal_detail = ""
		return
	var step: String = {
		"move_source": "Move power upstream.",
		"restore_drive": "Restore the drive.",
		"deliver_more": "Collect four more plates.",
		"ready": "Upstream drive restored.",
	}[report.phase]
	objective_title = "UPSTREAM DRIVE"
	goal_text = "%s\n%d / %d collected" % [step, report.products, report.target]
	var details: Dictionary = engineering_presenter.evaluate()
	goal_detail = str(details.get("diagnostic_text", "")) + "\n" + str(details.get("tradeoff_text", ""))

# A local read-only picker for the same site triangles shown by the view.
# Shared clients have no authority or character floor body of their own.
const TRANSMISSION_TERRAIN_PICK_LAYER := 32

func _install_transmission_terrain_picker() -> void:
	if ProductionEnvironment.Surface == null or has_node("TransmissionTerrainPicker"):
		return
	var terrain := StaticBody3D.new()
	terrain.name = "TransmissionTerrainPicker"
	terrain.set_meta("transmission_terrain", true)
	terrain.collision_layer = TRANSMISSION_TERRAIN_PICK_LAYER
	terrain.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(ProductionEnvironment.Surface.faces())
	var collider := CollisionShape3D.new()
	collider.shape = shape
	terrain.add_child(collider)
	add_child(terrain)

# Find the highest point of the emitted terrain triangles inside a footprint.
# Clipping the triangles also catches peaks and diagonal edges between samples.
func _transmission_terrain_high(x: float, z: float, half_x: float, half_z: float) -> float:
	var surface = ProductionEnvironment.Surface
	if not surface.contains(x - half_x, z - half_z) or not surface.contains(x + half_x, z + half_z):
		return NAN
	var first: Vector2i = surface.cell(x - half_x, z - half_z)
	var last: Vector2i = surface.cell(x + half_x, z + half_z)
	var high := -INF
	for gz in range(first.y, last.y + 1):
		for gx in range(first.x, last.x + 1):
			var a: Vector3 = surface.vertex(gx, gz)
			var b: Vector3 = surface.vertex(gx + 1, gz)
			var c: Vector3 = surface.vertex(gx + 1, gz + 1)
			var d: Vector3 = surface.vertex(gx, gz + 1)
			for triangle in [[a, b, c], [a, c, d]]:
				var polygon: Array = triangle
				for clip in [[0, x - half_x, 1.0], [0, x + half_x, -1.0], [2, z - half_z, 1.0], [2, z + half_z, -1.0]]:
					var clipped: Array = []
					for n in polygon.size():
						var p: Vector3 = polygon[n]
						var q: Vector3 = polygon[(n + 1) % polygon.size()]
						var inside: bool = (p[clip[0]] - clip[1]) * clip[2] >= 0.0
						var next_inside: bool = (q[clip[0]] - clip[1]) * clip[2] >= 0.0
						if inside:
							clipped.append(p)
						if inside != next_inside:
							clipped.append(p.lerp(q, (clip[1] - p[clip[0]]) / (q[clip[0]] - p[clip[0]])))
					polygon = clipped
				for p: Vector3 in polygon:
					high = maxf(high, p.y)
	return high

func _transmission_terrain_level(point: Vector3, x: float, z: float) -> int:
	var level := ceili(point.y / PITCH)
	if transmission_controls.active_tool not in ["place_shaft", "gear", "gearbox", "vertical_gearbox", "chain_drive"]:
		return level * Geometry.HEIGHT_DENOMINATOR
	var axis: String = transmission_controls.selected_axis
	var axle := Vector3(0.1, 0.1, 0.1)
	axle[["x", "y", "z"].find(axis)] = PITCH / 2.0
	var footprints: Array = [axle]
	if transmission_controls.active_tool == "gear":
		var disc := Vector3.ONE * PITCH / 2.0
		disc[["x", "y", "z"].find(axis)] = 0.04
		footprints.append(disc)
	elif transmission_controls.active_tool in ["gearbox", "vertical_gearbox", "chain_drive"]:
		footprints = [Vector3.ONE * PITCH / 2.0]
	for half: Vector3 in footprints:
		var high := _transmission_terrain_high(x, z, half.x, half.z)
		if is_finite(high):
			level = maxi(level, ceili((high - Geometry.ANCHOR_HEIGHT + half.y - 0.000000001) / PITCH))
	return level * Geometry.HEIGHT_DENOMINATOR

func _transmission_center(screen: Vector2) -> Array:
	if transmission_controls == null:
		return []
	var origin := camera.project_ray_origin(screen)
	var hit := _screen_pick(screen)
	if not hit.is_empty():
		var hit_id := _picked_target_id(hit)
		if transmission_controls.active_tool == "place_shaft":
			var pulley_target := _belt_pulley_target(hit_id, hit.position)
			if not pulley_target.is_empty():
				return pulley_target
		var target := _transmission_snap_target(hit_id, hit.normal, origin)
		if not target.is_empty():
			return target
	if transmission_controls.auto_height:
		var terrain_ray := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen) * 80.0)
		terrain_ray.collision_mask = TRANSMISSION_TERRAIN_PICK_LAYER
		var terrain_hit := get_world_3d().direct_space_state.intersect_ray(terrain_ray)
		if not terrain_hit.is_empty():
			var point: Vector3 = terrain_hit.position
			var x := roundi(point.x / PITCH)
			var z := roundi(point.z / PITCH)
			var level := _transmission_terrain_level(point, x * PITCH, z * PITCH)
			transmission_controls.snapped_height = level
			return [x * 4, level, z * 4]
	transmission_controls.snapped_height = 0
	var height: int = 0 if transmission_controls.auto_height else transmission_controls.gear_height
	var plane := Plane(Vector3.UP, Geometry.ANCHOR_HEIGHT + height * PITCH / 4.0)
	var point: Variant = plane.intersects_ray(origin, camera.project_ray_normal(screen))
	if point == null:
		return []
	return [roundi(point.x / PITCH) * 4, height, roundi(point.z / PITCH) * 4]

func _belt_pulley_target(entity_id: String, hit_position: Vector3) -> Array:
	var span: Variant = state.get("belt_spans", {}).get(entity_id)
	if not span is Dictionary or not hit_position.is_finite():
		return []
	var parts: Dictionary = state.get("transmission_parts", {})
	var first: Variant = parts.get(span.get("from", ""))
	var last: Variant = parts.get(span.get("to", ""))
	if not first is Dictionary or not last is Dictionary or first.get("kind") != "shaft" or last.get("kind") != "shaft":
		return []
	var a: Variant = first.get("center")
	var b: Variant = last.get("center")
	if not a is Array or not b is Array or a.size() != 3 or b.size() != 3:
		return []
	for axis in 3:
		if typeof(a[axis]) != TYPE_INT or typeof(b[axis]) != TYPE_INT or a[axis] % 4 != 0 or b[axis] % 4 != 0:
			return []
	var start := Vector3(a[0], a[1], a[2])
	var difference := Vector3(b[0], b[1], b[2]) - start
	var steps := roundi(maxf(absf(difference.x), maxf(absf(difference.y), absf(difference.z))) / 4.0)
	if steps < 1 or steps > 19:
		return []
	for axis in 3:
		if difference[axis] != 0.0 and absf(difference[axis]) != steps * 4.0:
			return []
	var world_start := start * Geometry.HEIGHT_STEP + Vector3.UP * Geometry.ANCHOR_HEIGHT
	var world_delta := difference * Geometry.HEIGHT_STEP
	var index := clampi(roundi((hit_position - world_start).dot(world_delta) / world_delta.length_squared() * steps), 0, steps)
	var center := start + difference * float(index) / float(steps)
	transmission_controls.snapped_height = roundi(center.y)
	return [roundi(center.x), transmission_controls.snapped_height if transmission_controls.auto_height else transmission_controls.gear_height, roundi(center.z)]

func _transmission_snap_target(entity_id: String, normal: Vector3, eye: Vector3) -> Array:
	# Pick bodies identify confirmed construction. Use their common grid height
	# when following surfaces; the menu can still choose an absolute air level.
	if transmission_controls.active_tool in ["place_shaft", "gear", "gearbox", "vertical_gearbox", "chain_drive"]:
		var part: Variant = state.get("transmission_parts", {}).get(entity_id)
		if part is Dictionary and part.get("kind") in ["shaft", "gear", "gearbox", "vertical_gearbox", "chain_drive"]:
			var center: Variant = part.get("center")
			if not center is Array or center.size() != 3 or not normal.is_finite():
				return []
			for coordinate: Variant in center:
				if typeof(coordinate) != TYPE_INT or coordinate % 4 != 0:
					return []
			var axis := 0
			for candidate in [1, 2]:
				if absf(normal[candidate]) > absf(normal[axis]):
					axis = candidate
			if absf(normal[axis]) < 0.5:
				return []
			var adjacent: Array = center.duplicate()
			adjacent[axis] += 4 if normal[axis] > 0.0 else -4
			transmission_controls.snapped_height = adjacent[1]
			adjacent[1] = adjacent[1] if transmission_controls.auto_height else transmission_controls.gear_height
			return adjacent
	var surface: Dictionary = state.get("foundations", {}).get(entity_id, {})
	if not surface.is_empty():
		var level: int = int(surface.get("level", 0))
		# Foundation slabs can end halfway between transmission tile levels.
		# Select the first shared tile at or above the top, including below zero.
		level = ceili(float(level) / Geometry.HEIGHT_DENOMINATOR) * Geometry.HEIGHT_DENOMINATOR
		transmission_controls.snapped_height = level
		return [int(surface.cell[0]) * 4, level if transmission_controls.auto_height else transmission_controls.gear_height,
			int(surface.cell[1]) * 4]
	var machine: Dictionary = state.get("entities", {}).get(entity_id, {})
	if machine.is_empty():
		return []
	var level: int = int(machine.get("level", 0))
	if level % Geometry.HEIGHT_DENOMINATOR != 0:
		return []
	var axis: int = ["x", "y", "z"].find(transmission_controls.selected_axis)
	if transmission_controls.active_tool in ["gearbox", "vertical_gearbox"] and typeof(machine.get("axis")) == TYPE_INT:
		axis = int(machine.axis)
	if axis < 0:
		return []
	var center := Vector3(machine.cell[0] * PITCH, level * Geometry.HEIGHT_STEP + Geometry.ANCHOR_HEIGHT,
		machine.cell[1] * PITCH)
	var side: float = normal[axis]
	if absf(side) < 0.5:
		side = (eye - center)[axis]
	var point := [int(machine.cell[0]) * 4, level, int(machine.cell[1]) * 4]
	point[axis] += 4 if side >= 0.0 else -4
	transmission_controls.snapped_height = point[1]
	point[1] = point[1] if transmission_controls.auto_height else transmission_controls.gear_height
	return point

func _transmission_click(center: Array, entity_id: String) -> bool:
	return _native_transmission() and transmission_controls != null and transmission_controls.handle_world_click(center, entity_id)

func _send_character_input(direction: Vector2, jump: bool) -> void:
	if actor_world != null:
		actor_world.set_control(client, direction, jump)

func _release_character_input() -> void:
	if actor_world != null:
		actor_world.release_control(client)

func _release_character_controls() -> void:
	if character_presenter != null:
		character_presenter.release()

func configure_save_slot(path: String) -> void:
	# The launcher supplies a fresh external session directory. One cooperating
	# writer owns this slot; this is not a cross-process filesystem lock.
	save_slot = path
	save_slot_owned = false
	save_slot_ready = path.is_absolute_path() and not path.begins_with("res://") and not path.begins_with("user://") and DirAccess.dir_exists_absolute(path.get_base_dir()) and not _path_exists(path) and not _path_exists(path + ".pending")

func _path_exists(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)

func _save_worksite() -> Dictionary:
	if explanation_open or not save_slot_ready:
		last_save_result = {"accepted": false, "reason": "save_unavailable"}
	elif not save_slot_owned and _path_exists(save_slot):
		last_save_result = {"accepted": false, "reason": "existing_destination"}
	else:
		var physical: Dictionary = actor_world.checkpoint_status() if actor_world != null else {"accepted": false, "reason": "actor_unready"}
		last_save_result = Store.write(model, save_slot) if physical.accepted else {"accepted": false, "reason": physical.reason}
		last_save_result["native_preflight"] = physical.duplicate(true)
	if last_save_result.accepted:
		save_slot_owned = true
		_message("Worksite saved. Reopen this save through the launcher in a new session.")
	else:
		_message("Save unavailable. Your current worksite and previous save are kept.", true)
	_refresh_ui()
	return last_save_result

func _load_worksite(path: String = "", startup_resume := false) -> Dictionary:
	if not startup_resume:
		last_load_result = {"accepted": false, "reason": "load_requires_restart"}
		_message("Reopen the saved worksite through the launcher in a new session. The live worksite is kept.", true)
		return last_load_result
	if explanation_open or not save_slot_ready:
		last_load_result = {"accepted": false, "reason": "load_unavailable"}
	else:
		last_load_result = Store.read_into(model, save_slot if path.is_empty() else path)
	if last_load_result.accepted:
		# Restored revision/order may be lower or equal. Invalidate presentation
		# caches instead of altering the restored authoritative version.
		if transmission_controls != null:
			transmission_controls.clear_belt_selection()
		selected = ""
		pending_link = ""
		geometry_key = ""
		visual_revision = -1
		item_visual_key = []
		elapsed = 0.0
		request_sequence = 0
		request_namespace = "opening-" + Crypto.new().generate_random_bytes(16).hex_encode() + "-"
		# A restored completed order is already known; reopening is not a new receipt.
		workshop_completion_observed = null
		_refresh()
		_message("Worksite loaded. Select a machine to continue.")
	else:
		_message("Load refused. Your current worksite and previous save are kept.", true)
	return last_load_result

func _construction_feedback(intent: Dictionary, outcome: Dictionary) -> void:
	if ConstructionAudio.cue_for(intent).is_empty() or not outcome.get("accepted", false):
		return
	if construction_audio == null:
		construction_audio = ConstructionAudio.new()
		construction_audio.name = "ConstructionAudio"
		add_child(construction_audio)
	construction_audio.confirmed(intent, outcome, str(outcome.get("context", state.get("context", ""))))

func _crank_turn_refusal(machine: String) -> String:
	return "Place a crafted hand crank at this %s's input before turning it." % machine

func _confirm_hand_crank_visual(action: Dictionary, outcome: Dictionary) -> void:
	if action.get("action") == "operate_hand_crank" and outcome.get("accepted", false) \
			and transmission_presenter != null:
		transmission_presenter.confirmed_hand_crank_pulse(str(action.get("entity", "")), outcome)

func _reclaim_owned_drops(entity: String) -> Array[Dictionary]:
	var part: Dictionary = state.get("placed_components", {}).get(entity, {})
	if part.is_empty():
		return []
	var centers: Array = []
	var broad_member := false
	for press: Dictionary in state.get("broad_press_assemblies", []):
		var parts: Dictionary = press.get("parts", {})
		if parts.get("anvils", []).has(entity) or parts.get("heads", []).has(entity) \
				or parts.get("slide", "") == entity:
			var origin: Array = press.get("origin", [])
			if origin.size() == 3:
				centers.append(origin)
				broad_member = true
	if not broad_member and part.get("component", "") in ["anvil", "broad_anvil", "receiver_tray"]:
		centers.append(part.get("center", []))
	for key in ["sliding_press_assemblies", "guided_press_assemblies"]:
		for press: Dictionary in state.get(key, []):
			if not press.get("parts", {}).values().has(entity):
				continue
			var work: Array = press.get("work_center", press.get("center", []))
			if work.size() != 3:
				continue
			centers.append(work)
			var exits: Array = []
			if key == "sliding_press_assemblies":
				exits = [[int(work[0]) - 1, work[1], work[2]],
					[int(work[0]) + 1, work[1], work[2]]]
			else:
				for route: Dictionary in press.get("open_feeds", []):
					exits.append(route.get("exit", []))
			for exit_center: Array in exits:
				for drop: Dictionary in state.get("dropped_material", []):
					if drop.get("center", []) == exit_center and int(drop.get("products", 0)) > 0:
						centers.push_front(exit_center)
	var result: Array[Dictionary] = []
	for center: Array in centers:
		if result.any(func(item: Dictionary) -> bool: return item.center == center):
			continue
		for drop: Dictionary in state.get("dropped_material", []):
			if drop.get("center", []) == center:
				result.append(drop)
				break
	return result

func issue(action: Dictionary) -> Dictionary:
	if explanation_open:
		return {"accepted": false, "reason": "explanation_open"}
	if startup_save_pending:
		_message("Finishing the saved worksite's opening. Wait a moment.")
		return {"accepted": false, "reason": "worksite_starting"}
	if action.get("action", "") == "reclaim_component":
		for drop: Dictionary in _reclaim_owned_drops(str(action.get("entity", ""))):
			var expected := drop.duplicate(true)
			expected.erase("center")
			var pickup := issue({"action": "pickup_material", "center": drop.center,
				"expected": expected})
			if not pickup.get("accepted", false):
				return pickup
	if actor_world != null:
		for actor in model.projection().actors:
			actor_world.ensure_actor(actor)
	request_sequence += 1
	var intent: Dictionary = action.duplicate(true)
	intent.merge({"context": model.projection().context, "client": client,
		"request": request_namespace + str(request_sequence)}, true)
	var outcome: Dictionary = model.command(intent)
	if actor_world != null:
		actor_world.sync_topology()
	if outcome.accepted:
		if action.action in ["place_gear", "place_shaft"]:
			selected = str(outcome.get("entity", ""))
		elif action.action == "stow_fabrication_hub" and selected == action.get("entity", ""):
			selected = ""
		elif action.action in ["remove", "remove_belt_span"] and selected == action.get("entity", ""):
			selected = ""
		_construction_feedback(intent, outcome)
		if action.action != "set_developer_conveniences":
			_message(_harvest_result_text(outcome) if action.action == "harvest_source" else {"place": "Placed. Parts stay with this worksite.",
			"craft_component": "Component crafted from carried material.",
			"field_craft": "Wooden component shaped with your multitool.",
			"craft_part": "Transmission kit made from carried timber and copper.",
			"place_component": "Component placed on the shared grid.",
			"attach_hand_crank": "Hand crank placed beside the rotary input.",
			"detach_hand_crank": "The same hand crank returned to your inventory.",
			"operate_hand_crank": "Crank turning.",
			"turn_slide_crank": "The placed crank advanced the slide.",
			"reclaim_component": "Component returned to your carried cargo.",
			"stow_fabrication_hub": "Pod workshop unbolted. Place it on clear ground or a foundation top.",
			"deploy_fabrication_hub": "Pod workshop installed at its new worksite.",
			"turn_hand_crank": "Collector cut a piece of copper into its receiver tray.",
			"feed_press": "One carried copper piece is now under the press head.",
			"turn_press_crank": "Plate formed at outlet. Collect it [P]." if int(outcome.get("formed_products", 0)) > 0 else "Press work advanced. Turn again to finish the plate.",
			"place_foundation": "Foundation placed. Its surface shares the machine grid.",
			"place_foundations": "Foundation area placed on the world grid.",
			"connect": "Material path connected.", "connect_drive": "Drive shaft connected.",
			"retrieve": "Plate collected.", "pickup_material": "Loose material collected.", "load_belt_slot": "Material placed on the belt.",
			"push_channel_sheet": "Sheet moved one workcell along the channel.",
			"push_channel_small": "Material moved to the next channel cell.",
			"remove": "Part returned to your carried kit.",
			"disconnect": "Material connection removed.",
			"disconnect_drive": "Drive shaft returned."}.get(action.action, "Done."))
	else:
		var refusal := _material_refusal_message(outcome, {"occupied": "That square is occupied.", "no_part": "That part is already placed.",
			"ports_not_adjacent": "Connect neighboring ports, following the arrow.",
			"invalid_belt_axis": "The belt's drive shaft runs across the belt, perpendicular to material travel.",
			"missing_entity": "Choose a placed machine at each end.",
			"already_connected": "Those ports are already connected.",
			"unavailable_output": "There is no finished copper plate to collect yet.",
			"out_of_reach": "Move closer to the target before building or interacting.",
			"crank_not_attached": "Place a crafted hand crank at a rotary input before turning it.",
			"crank_disconnected": "This crank has no connected shaft. Rebuild the route or reclaim it [F].",
			"input_already_driven": "A self-powered source already drives this shaft network.",
			"input_port_occupied": "That input already holds a crank or another part.",
			"wrong_input_port": "Place the crank at an exposed rotary input.",
			"wrong_drive_shaft": "Use this press's fitted drive shaft.",
			"incomplete_assembly": "The press still needs the indicated component.",
			"receiver_full": "Pick up the copper in the collector receiver before cutting again.",
			"blocked_feed": "Choose a clear feed face.",
			"blocked_exit": "Choose a clear lower exit.",
			"input_full": "Recover or process the existing copper first.",
			"unavailable_input": "Carry copper or feed the selected press first.",
			"site_occupied": "Rock or scenery blocks that placement or press route.",
			"stand_in_use": "A neighboring stand occupies that space. Reclaim its machine, then try again.",
			"unsupported_bench": "Set the workbench on clear ground or a foundation top.",
			"not_holder": "Only the worker carrying the pod workshop can place it.",
			"already_stowed": "The pod workshop is already carried.",
			"actor_unready": "Your character is not ready yet. Wait a moment.",
			"actor_occupied": "A character is in that square. Move clear before placing the machine.",
			"powered": "Stop the drive before changing the machinery.",
			"not_stopped": "Stop the drive before changing the machinery.",
			"held_stock": "Retrieve the material before removing this machine.",
			"contains_stock": "Retrieve the material before removing this machine.",
			"not_at_stream": "Set the wheel in the water with its lower rim immersed and clear of the bed.",
			"not_at_seam": "Place the collector on the ore-bearing ground.",
			"no_shaft": "All carried shafts are in use."}.get(outcome.reason, "That action is unavailable here."), action.action)
		if action.action == "craft_component":
			refusal = {"unavailable_input": "Gather the timber or copper shown for this component.",
				"out_of_reach": "Move beside the selected workshop to craft this component."}.get(outcome.get("reason", ""), refusal)
		elif action.action == "field_craft":
			refusal = {"unavailable_input": "Gather the timber shown for this component.",
				"unavailable_recipe": "Metal components need a workshop."}.get(outcome.get("reason", ""), refusal)
		elif action.action == "craft_part":
			refusal = {"unavailable_input": "Gather the timber or copper shown for this transmission kit.",
				"out_of_reach": "Move beside the selected workshop to make a transmission kit.",
				"quantity_overflow": "Too many of this kit are already carried."}.get(outcome.get("reason", ""), refusal)
		elif action.action == "place_component" and outcome.get("reason", "") == "no_component":
			refusal = "Carry another %s." % str(action.get("component", "component")).replace("_", " ")
		elif action.action == "turn_hand_crank":
			refusal = {"crank_not_attached": "Fit a crafted hand crank to the collector input.",
				"incomplete_assembly": "Fit the collector's missing component before cutting ore.",
				"source_depleted": "This ore deposit is depleted.",
				"output_full": "Clear a loose material drop before cutting more ore.",
				"out_of_reach": "Move beside the collector mount to turn it."}.get(outcome.get("reason", ""), refusal)
		elif action.action == "deploy_fabrication_hub" and outcome.get("reason", "") == "unsupported_bench":
			refusal = "Set the pod workshop on clear ground or a foundation top."
		_message(refusal, true)
	_refresh()
	_confirm_hand_crank_visual(action, outcome)
	return outcome

func _harvest_result_text(outcome: Dictionary) -> String:
	var timber: int = outcome.get("moved_timber", 0)
	if timber > 0:
		return "Collected %d timber." % timber
	var raw: int = outcome.get("moved_raw", 0)
	if raw == 0:
		return "Cutting…"
	return "Collected %d copper %s." % [raw, "piece" if raw == 1 else "pieces"]

func _press_contact_refusal(entity: String) -> String:
	for assembly: Variant in state.get("guided_press_assemblies", []):
		if not assembly is Dictionary or assembly.get("anvil", "") != entity:
			continue
		match assembly.get("status", ""):
			"missing_ram": return "No working face contacts this support."
			"missing_guide": return "The working face has no guided stroke."
			"missing_shaft", "missing_cog": return "No rotary input reaches this working face."
	return "No compatible working face acts on this support."

func _material_refusal_message(outcome: Dictionary, fallback: String, action_name: String = "") -> String:
	if _native_transmission() and action_name in ["place_belt_span", "place_selected_belt_span"] \
			and outcome.get("reason", "") == "actor_occupied" and not outcome.get("uncertain", false):
		return "Move clear of the belt's path before connecting these shafts."
	var advice: String = {
		"first_plate_required": "Carry your first copper plate to unlock that part.",
		"unavailable_source": "That source is unavailable or depleted. Choose another tree or ore deposit.",
		"source_occluded": "Move around the obstacle before harvesting.",
		"unaligned_elevation": "Machines and wheels need a whole-tile height. Build a factory floor with Access steps off, or adjust the wheel's drive height.",
		"axles_already_touch": "These axle ends already touch; no shaft is needed.",
		"overlapping_shafts": "A shaft already occupies that length. Place the new segment end to end.",
		"foundation_required": "Build a foundation here first so the machine has a level surface.",
		"invalid_area": "Choose a rectangle of at most 256 foundation tiles.",
		"foundation_in_use": "Remove the machinery on this foundation before reclaiming it.",
		"site_occupied": "Rock or vegetation occupies this space. Choose a clear location.",
		"terrain_unavailable": "There is no confirmed building surface here."}.get(outcome.get("reason", ""), "")
	if not advice.is_empty():
		return advice
	if _native_transmission() and action_name == "load_belt_slot" \
			and outcome.get("reason") == "belt_cannot_carry" and not outcome.get("uncertain", false):
		return "This belt is too narrow for broad work. Carry it to the next machine."
	if _native_transmission() and action_name == "load_belt_slot" \
			and outcome.get("reason") == "belt_path_cannot_carry" and not outcome.get("uncertain", false):
		return "This belt transmits rotation but cannot carry items along this path."
	if _native_transmission() and action_name in ["push_channel_sheet", "push_channel_small"] \
			and not outcome.get("uncertain", false):
		var small_item: bool = action_name == "push_channel_small"
		var channel_advice: String = {
			"unavailable_input": "That item is no longer at the chosen square. Inspect the loose material again.",
			"partial_shear": "A partly cut sheet must be finished or recovered before moving.",
			"missing_channel": "Build a narrow or broad channel in the direction of travel before pushing this item." if small_item else "Build a broad channel in the direction of travel before pushing this copper sheet.",
			"blocked_channel": "The item needs a supported square and a clear receiver. Clear or extend the channel." if small_item else "The full copper sheet needs two supported squares and a clear swept route. Clear or extend the channel.",
			"invalid_channel_target": "Push toward the next channel cell along X or Z at the item's current height." if small_item else "Push one whole tile along X or Z at the sheet's current height."}.get(outcome.get("reason", ""), "")
		if not channel_advice.is_empty():
			return channel_advice
	if _native_transmission() and action_name == "stroke_broad_shear" and not outcome.get("uncertain", false):
		var shear_advice: String = {"output_full": "Clear the other anvil squares before cutting the copper sheet.",
			"shear_unpowered": "Drive the cutting head forward before cutting."}.get(outcome.get("reason", ""), "")
		if not shear_advice.is_empty():
			return shear_advice
	if recovery_actions != null:
		var text: String = recovery_actions.refusal_text(outcome)
		if not text.is_empty():
			return text
	if _native_transmission() and action_name in ["feed_press", "refeed_press_work", "turn_press_crank"] \
			and outcome.get("reason") == "incomplete_assembly" \
			and not outcome.get("uncertain", false):
		return _press_contact_refusal(str(outcome.get("entity", "")))
	if _native_transmission() and outcome.get("reason") == "not_at_seam":
		return "Place the collector on the ore-bearing ground. A foundation at factory floor height can support it."
	return fallback

func _process(delta: float) -> void:
	_sync_mouse_capture()
	_update_fps_counter(delta)
	_advance_held_crank(delta)
	if actor_world != null:
		actor_world.set_belt_step_seconds(STEP_SECONDS if auto_advance else 0.0)
	if auto_advance:
		elapsed += delta
		var advanced: Dictionary = {}
		while elapsed >= STEP_SECONDS:
			elapsed -= STEP_SECONDS
			advanced = model._advance_borrowed() if model is NativeWorldModel else model.advance()
		if advanced.has("context") and advanced.has("revision") and advanced.has("entities"):
			_refresh_from_projection(advanced)
		elif model is NativeWorldModel and not state.is_empty():
			var borrowed := (model as NativeWorldModel)._view_projection_borrowed()
			if borrowed.get("revision") != state.get("revision") \
					or borrowed.get("order") != state.get("order") \
					or borrowed.get("context") != state.get("context"):
				_refresh_from_projection(borrowed)
			elif borrowed.get("actors", {}).get(client) != state.get("actors", {}).get(client):
				var prev_actor: Dictionary = state.get("actors", {}).get(client, {})
				var next_actor: Dictionary = borrowed.get("actors", {}).get(client, {})
				state = borrowed
				if character_presenter != null and (next_actor.get("position") != prev_actor.get("position") \
						or next_actor.get("ready") != prev_actor.get("ready")):
					character_presenter.refresh()
				if next_actor.get("ready") != prev_actor.get("ready"):
					_refresh_ui()
		else:
			_refresh()
	_refresh_machine_preview()
	_refresh_component_preview()
	_refresh_placement_options()
	_refresh_water()
	_refresh_mechanical_audio()
	_animate_wheel(delta)
	if explanation_open:
		return
	_update_camera()
	_advance_arrival_reveal(delta)
	if _object_menu_open() and Vector2i(get_viewport().get_visible_rect().size) != object_menu_viewport_size:
		_fit_object_menu()
	_refresh_pointed_summary()

func _update_fps_counter(delta: float) -> void:
	if fps_label == null or not is_finite(delta) or delta <= 0.0:
		return
	fps_elapsed += delta
	if fps_elapsed >= 0.25:
		fps_elapsed = fmod(fps_elapsed, 0.25)
		fps_label.text = "FPS %d" % maxi(0, roundi(Engine.get_frames_per_second()))

func _water_time_seconds() -> float:
	return float(Time.get_ticks_msec()) * 0.001

func _refresh_water() -> void:
	if ProductionEnvironment.Surface != null:
		ProductionEnvironment.animate_water(_water_time_seconds())

func _refresh_mechanical_audio() -> void:
	var ready := _can_control_character() and _native_transmission() and camera != null
	if not ready:
		if mechanical_ambience != null:
			mechanical_ambience.silence()
		return
	if mechanical_ambience == null:
		mechanical_ambience = MechanicalAmbience.new()
		mechanical_ambience.name = "MechanicalAmbience"
		add_child(mechanical_ambience)
	mechanical_ambience.sync(state, client, true, camera.global_basis, model is NativeWorldModel)

func _animate_wheel(delta: float) -> void:
	if _native_transmission():
		if transmission_presenter == null:
			return
		transmission_presenter.advance_visual_motion(delta)
		machine_batches.wheel_batch_poses.clear()
		machine_batches.wheel_updated_rotors.clear()
		var cull_far_joinery := camera != null and camera.is_inside_tree() and not machine_batches.machine_batched_rotors.is_empty()
		var listener_position := camera.global_position if cull_far_joinery else Vector3.ZERO
		var frustum: Array = camera.get_frustum() if camera != null and camera.is_inside_tree() else []
		for cell in machine_rotor_cells:
			var bounds: AABB = cell.bounds
			var minimum := bounds.position
			var maximum := bounds.end
			var cell_outside := false
			for plane: Plane in frustum:
				# The nearest corner has the minimum plane distance. Culling it
				# excludes only cells whose every wheel is beyond the old margin.
				var nearest := Vector3(minimum.x if plane.normal.x >= 0.0 else maximum.x,
					minimum.y if plane.normal.y >= 0.0 else maximum.y,
					minimum.z if plane.normal.z >= 0.0 else maximum.z)
				if plane.distance_to(nearest) > WHEEL_MOTION_VISIBILITY_MARGIN:
					cell_outside = true
					break
			if cell_outside:
				continue
			for wheel in cell.wheels:
				# Keep nearby offscreen wheels live for their shadows. The confirmed
				# cosmetic phase still advances when its hidden pose is held.
				var outside_view := false
				for plane: Plane in frustum:
					if plane.distance_to(wheel.center) > WHEEL_MOTION_VISIBILITY_MARGIN:
						outside_view = true
						break
				if outside_view:
					continue
				var basis: Basis = wheel.base * Basis(Vector3.BACK, transmission_presenter.visual_angle(wheel.id))
				var rotor_id: int = wheel.rotor.get_instance_id()
				machine_batches.wheel_updated_rotors[rotor_id] = true
				# The full core is already in a MultiMesh. Beyond the last paddle
				# detail range, advance that instance without dirtying the many
				# hidden and distance-culled source nodes under its rotor.
				if cull_far_joinery and machine_batches.machine_batched_rotors.has(rotor_id) \
						and listener_position.distance_squared_to(wheel.center) > WHEEL_DETAIL_UPDATE_RADIUS * WHEEL_DETAIL_UPDATE_RADIUS:
					machine_batches.wheel_batch_poses[rotor_id] = Transform3D(basis, wheel.rotor.position)
				else:
					wheel.rotor.basis = basis
		_animate_machine_bodies(delta)
		machine_batches.update(true)
		return
	# Historical scripted presentation remains separate. Native cosmetic
	# angles above are neither a simulation clock nor saved/contact phase.
	if wheel_rotor != null and state.get("powered", false) and not state.get("options", {}).get("native", false):
		wheel_rotor.rotation.z += delta * 0.8

func _remember_machine_motion(node: Node3D, kind: String, pose: Transform3D,
		rows: Array[Dictionary]) -> void:
	if node is MeshInstance3D:
		var part_name := str(node.name)
		var role := ""
		if kind == "collector" and (part_name in ["CutterDrum", "CutterHub"] or node.get_meta("detail_role", "") == "CutterFlute"):
			role = "cutter"
		elif kind == "processor" and part_name in ["ToolHead", "Piston"]:
			role = "head" if part_name == "ToolHead" else "rod"
		if not role.is_empty():
			rows.append({"node": node, "role": role, "rest": pose,
				"parent_inverse": (pose * node.transform.affine_inverse()).affine_inverse()})
	for child in node.get_children():
		if child is Node3D:
			_remember_machine_motion(child, kind, pose * child.transform, rows)

func _animate_machine_bodies(delta: float) -> void:
	if not _can_present_confirmed_motion() or not is_finite(delta) or delta <= 0 or machine_root == null or transmission_presenter == null:
		return
	_sync_machine_body_context()
	for anchor in machine_motion_anchors:
		var kind: String = anchor.get_meta("machine_kind", "")
		var id: String = anchor.get_meta("machine_entity", "")
		var rows: Array = anchor.get_meta("motion_meshes", [])
		if kind == "collector":
			var angle: float = transmission_presenter.visual_angle(id)
			if angle == float(anchor.get_meta("cutter_angle", NAN)):
				continue
			_apply_cutter_pose(anchor, rows, angle)
		elif kind == "belt":
			_apply_conveyor_motion(anchor, transmission_presenter.visual_rotation(id))
		elif kind == "processor":
			var target: Variant = _observed_press_target()
			var generation: Variant = state.get("entities", {}).get(id, {}).get("generation")
			if target == null or typeof(generation) != TYPE_INT or generation < 1:
				continue
			# A pose follows observed held work, including blocked READY. It does
			# not predict a cycle, release a plate or advance remaining ticks.
			if not machine_press_poses.has(id):
				machine_press_poses[id] = {"generation": generation, "travel": target}
				_apply_press_pose(rows, target)
				continue
			var previous: float = machine_press_poses[id].travel
			var travel: float = move_toward(previous, float(target), minf(delta, 0.1) * 0.12)
			if travel == previous:
				continue
			_apply_press_pose(rows, travel)
			machine_press_poses[id].travel = travel

func _apply_conveyor_motion(anchor: Node3D, rotation: float) -> void:
	var loop: MeshInstance3D
	if anchor.has_meta("conveyor_loop"):
		loop = anchor.get_meta("conveyor_loop") as MeshInstance3D
	if not is_instance_valid(loop):
		loop = anchor.find_child("ConveyorLoop", true, false) as MeshInstance3D
		anchor.set_meta("conveyor_loop", loop)
	if loop == null or not loop.material_override is StandardMaterial3D:
		return
	var length_value := 4.0 * ProductionConveyorArt.HALF_SPAN + TAU * ProductionConveyorArt.RADIUS
	var repeats := maxi(1, roundi(length_value / ProductionConveyorArt.SOURCE_METRES))
	# The top profile runs toward +X as UV increases. Positive +Z shaft
	# rotation carries the top toward -X, so the texture offset increases.
	var direction := -1.0 if anchor.get_meta("material_rotated", false) else 1.0
	var offset := fposmod(direction * rotation * ProductionConveyorArt.RADIUS * repeats / length_value, 1.0)
	var slot: Dictionary = machine_batches.machine_conveyor_batch_slots.get(loop.get_instance_id(), {})
	if not slot.is_empty():
		# The visible batch reads custom data; the source material is hidden.
		slot.mesh.set_instance_custom_data(slot.index, Color(offset, 0, 0))
		return
	loop.material_override.uv1_offset = Vector3(offset, 0, 0)

func _sync_machine_body_context() -> void:
	var context: Variant = state.get("context")
	if typeof(context) != TYPE_STRING or context != machine_body_context:
		machine_press_poses.clear()
		machine_body_context = context if typeof(context) == TYPE_STRING else ""
	for id in machine_press_poses.keys():
		var entity: Dictionary = state.get("entities", {}).get(id, {})
		if entity.get("kind") != "processor" or typeof(entity.get("generation")) != TYPE_INT or entity.get("generation") != machine_press_poses[id].generation:
			machine_press_poses.erase(id)

func _observed_press_target() -> Variant:
	var stock: Variant = state.get("stock")
	var held: Variant = stock.get("held") if stock is Dictionary else null
	var remaining: Variant = state.get("remaining")
	if typeof(held) != TYPE_INT or held < 0 or typeof(remaining) != TYPE_INT or remaining < 0:
		return null
	# The fitted billet boss reaches y = 0.732; the resting head's lower face
	# is at y = 0.755. Keep this pose clear of the unchanged workpiece.
	return 0.015 if held > 0 else 0.0

func _apply_cutter_pose(anchor: Node3D, rows: Array, angle: float) -> void:
	var spin := MachineBatcher.cutter_pose(anchor, angle)
	var slot: Dictionary = machine_batches.machine_cutter_batch_slots.get(anchor.get_instance_id(), {})
	if not slot.is_empty():
		slot.mesh.set_instance_transform(slot.index, anchor.transform * spin)
		anchor.set_meta("cutter_angle", angle)
		return
	for row in rows:
		if is_instance_valid(row.node) and row.role == "cutter":
			row.node.transform = row.parent_inverse * spin * row.rest
	anchor.set_meta("cutter_angle", angle)

func _apply_press_pose(rows: Array, travel: float) -> void:
	for row in rows:
		if not is_instance_valid(row.node):
			continue
		var pose: Transform3D = row.rest
		if row.role == "head":
			pose.origin.y -= travel
		elif row.role == "rod":
			pose.origin.y -= travel / 2.0
			pose.basis = pose.basis.scaled(Vector3(1, 1 + travel / 0.45, 1))
		row.node.transform = row.parent_inverse * pose

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_stop_held_crank()
		_release_character_controls()
		_release_mouse_capture()

func _exit_tree() -> void:
	_release_mouse_capture()

func _mouse_capture_allowed(window_focused: bool, popup_open: bool) -> bool:
	return distance <= 0.0 and window_focused and not popup_open \
		and _can_control_character() and (pause_exit_confirmation == null or not pause_exit_confirmation.visible)

func _wants_mouse_capture() -> bool:
	return _mouse_capture_allowed(DisplayServer.window_is_focused(),
		DisplayServer.window_get_active_popup() != DisplayServer.INVALID_WINDOW_ID)

func _release_mouse_capture() -> void:
	if not mouse_capture_owned:
		return
	mouse_capture_owned = false
	mouse_capture_skip_motion = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_mouse_menu_visibility_changed() -> void:
	if not _can_control_character():
		_release_character_controls()
		_stop_held_crank()
	_sync_mouse_capture()

func _sync_mouse_capture() -> void:
	if not _wants_mouse_capture():
		if mouse_capture_owned and (not DisplayServer.window_is_focused() or not _can_control_character()):
			_release_character_controls()
			_stop_held_crank()
		_release_mouse_capture()
		return
	if not mouse_capture_owned or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		mouse_capture_owned = true
		# Capture can warp the pointer. Ignore that first relative event.
		mouse_capture_skip_motion = true

func _rotate_camera_from_mouse(relative: Vector2) -> void:
	orbit_yaw -= relative.x * 0.007
	orbit_pitch = clampf(orbit_pitch + relative.y * 0.005,
		-1.25 if distance == 0.0 else 0.35, 1.25)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mouse_capture_owned and _wants_mouse_capture():
		if mouse_capture_skip_motion:
			mouse_capture_skip_motion = false
		else:
			_rotate_camera_from_mouse(event.relative)
			_update_camera()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.keycode == KEY_E and not event.pressed:
		_stop_held_crank()
	if arrival_reveal_active:
		if event is InputEventKey and event.pressed and not event.echo \
				and event.keycode in [KEY_SPACE, KEY_ESCAPE]:
			_finish_arrival_reveal(true)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.keycode == KEY_F3:
		if event.pressed and not event.echo and _can_control_character():
			issue({"action": "set_developer_conveniences", "enabled":
				not state.get("options", {}).get("developer_conveniences", false)})
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.keycode == KEY_ALT and not event.pressed \
			and component_nudge_active:
		component_nudge_active = false
		component_nudge_center.clear()
		_update_cursor()
		get_viewport().set_input_as_handled()
		return
	if _object_menu_open():
		if event is InputEventKey and event.pressed and not event.echo:
			var used := false
			if event.keycode in [KEY_ESCAPE, KEY_E]:
				object_menu.hide()
				used = true
			elif event.keycode == KEY_DELETE:
				used = _activate_button(arrival_assembly_controls.reclaim_button) \
					if arrival_assembly_controls != null and state.get("placed_components", {}).has(selected) \
					else _activate_button(remove_button)
			elif event.ctrl_pressed and event.keycode == KEY_R:
				used = _activate_button(retrieve_button)
			elif event.ctrl_pressed and event.keycode == KEY_M:
				used = _open_action_menu(recovery_actions.action_button if recovery_actions != null else null)
			elif event.ctrl_pressed and event.keycode == KEY_L:
				used = _open_action_menu(loose_material_controls)
			elif event.keycode == KEY_F5 and not startup_save_pending:
				_save_worksite()
				used = true
			elif event.keycode == KEY_F9:
				_load_worksite()
				used = true
			elif not event.ctrl_pressed and arrival_assembly_controls != null:
				var actions = arrival_assembly_controls
				match event.keycode:
					KEY_P: used = actions.inventory_shortcut(KEY_P) or _activate_button(actions.pickup_button)
					KEY_F: used = actions.inventory_shortcut(KEY_F) or _activate_button(actions.feed_button)
					KEY_N: used = _open_action_menu(actions.broad_refeed_button)
					KEY_X: used = _activate_button(actions.shear_button) or _activate_button(actions.collector_cut_button)
					KEY_R: used = actions.inventory_shortcut(KEY_R) or _activate_button(actions.refeed_work_button)
					KEY_U: used = actions.inventory_shortcut(KEY_U) or _activate_button(actions.recover_work_button)
					KEY_G: used = actions.cycle_feed_route()
					KEY_S: used = _open_action_menu(actions.sheet_button)
			if used:
				get_viewport().set_input_as_handled()
		return
	if pause_exit_confirmation != null and pause_exit_confirmation.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			pause_exit_confirmation.hide()
			get_viewport().set_input_as_handled()
		return
	if _pause_menu_open():
		if event is InputEventKey and event.pressed and not event.echo:
			var used := true
			match event.keycode:
				KEY_ESCAPE: pause_menu.hide()
				KEY_F5:
					if not startup_save_pending:
						_save_worksite()
				KEY_F9: _load_worksite()
				KEY_Q: pause_exit_confirmation.popup_centered()
				_: used = false
			if used:
				get_viewport().set_input_as_handled()
		return
	if manager_log_open:
		if event is InputEventKey:
			if event.pressed and not event.echo and event.keycode in [KEY_J, KEY_ESCAPE]:
				_toggle_manager_log()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_J \
			and not explanation_open and not _catalog_open():
		_toggle_manager_log()
		get_viewport().set_input_as_handled()
		return
	if explanation_open:
		if event is InputEventKey:
			if event.pressed and not event.echo:
				if event.keycode in [KEY_H, KEY_ESCAPE]:
					_toggle_explanation()
			get_viewport().set_input_as_handled()
		return
	if _catalog_open():
		return
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed and not event.echo:
		# PopupPanel can hide itself before this scene sees the same Escape.
		if object_menu_closed_frame == Engine.get_process_frames():
			get_viewport().set_input_as_handled()
			return
		if _cancel_active_construction():
			consumed_shortcut_keys[KEY_ESCAPE] = true
		else:
			_open_pause_menu()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.keycode == KEY_ALT and mode == "component":
		if event.pressed and not component_nudge_active:
			component_nudge_center = _component_pointed_center()
			component_nudge_active = true
		elif not event.pressed:
			component_nudge_active = false
			component_nudge_center.clear()
		_update_cursor()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and not event.pressed and consumed_shortcut_keys.has(event.keycode):
		consumed_shortcut_keys.erase(event.keycode)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var handled := false
		if event.alt_pressed and mode == "component" and event.keycode in [KEY_LEFT, KEY_RIGHT,
				KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN]:
			if not component_nudge_active:
				component_nudge_center = _component_pointed_center()
				component_nudge_active = true
			var axis := 1 if event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN] else \
				0 if event.keycode in [KEY_LEFT, KEY_RIGHT] else 2
			var kind: String = arrival_assembly_controls.selected_name() \
				if arrival_assembly_controls != null else ""
			var stride := Geometry.HEIGHT_DENOMINATOR if axis != 1 and kind in [
				"anvil", "flat_head", "wooden_slide", "copper_slide"] else 1
			var step := stride if event.keycode in [KEY_RIGHT, KEY_UP, KEY_PAGEUP] else -stride
			component_nudge_center[axis] = clampi(int(component_nudge_center[axis]) + step,
				-Geometry.GRID_COORDINATE_LIMIT, Geometry.GRID_COORDINATE_LIMIT)
			_update_cursor()
			handled = true
		elif event.ctrl_pressed:
			match event.keycode:
				KEY_R: handled = _activate_button(retrieve_button)
				KEY_M: handled = _open_action_menu(recovery_actions.action_button if recovery_actions != null else null)
				KEY_L: handled = _open_action_menu(loose_material_controls)
				KEY_HOME:
					if transmission_controls != null and transmission_controls.is_visible_in_tree():
						transmission_controls._height_selected(2)
						handled = true
		elif event.alt_pressed and transmission_controls != null and _native_transmission() and _can_choose_tool():
			var transmission_tools := {KEY_1: "gear", KEY_2: "drive", KEY_3: "belt",
				KEY_4: "gearbox", KEY_5: "vertical_gearbox", KEY_6: "chain_drive"}
			if transmission_tools.has(event.keycode):
				var choice: String = transmission_tools[event.keycode]
				var entry := building_hotbar.catalog_buttons.get(choice) as Button
				if entry != null and not entry.disabled:
					_select_tool(choice)
					handled = true
		elif not event.alt_pressed:
			match event.keycode:
				KEY_DELETE: handled = _activate_button(remove_button)
				KEY_T: handled = _open_action_menu(transmission_controls)
				KEY_X:
					if event.shift_pressed and transmission_controls != null and transmission_controls.is_visible_in_tree():
						var axes := ["x", "y", "z"]
						var next := (axes.find(transmission_controls.selected_link_axis) + 1) % 3
						if axes[next] == transmission_controls.selected_axis:
							next = (next + 1) % 3
						transmission_controls._link_axis_selected(next)
						handled = true
					elif placement_options_axis.is_visible_in_tree():
						handled = _activate_button(placement_options_axis)
				KEY_Z:
					if foundation_steps_toggle.is_visible_in_tree() and not foundation_steps_toggle.disabled:
						foundation_steps_toggle.button_pressed = not foundation_steps_toggle.button_pressed
						_set_foundation_steps(foundation_steps_toggle.button_pressed)
						handled = true
				KEY_V:
					if mode == "component" and arrival_assembly_controls != null \
							and arrival_assembly_controls.selected_name() in [
								"anvil", "broad_anvil", "flat_head", "broad_flat_head",
								"copper_slide", "broad_copper_slide"]:
						_toggle_component_footprint()
						handled = true
					elif foundation_area_toggle.is_visible_in_tree() and not foundation_area_toggle.disabled:
						foundation_area_toggle.button_pressed = not foundation_area_toggle.button_pressed
						foundation_area_mode = foundation_area_toggle.button_pressed
						foundation_area_started = false
						handled = true
				KEY_K:
					if transmission_controls != null and transmission_controls.is_visible_in_tree() and mode == "gear":
						transmission_controls._size_selected(1 if transmission_controls.gear_teeth == 2 else 0)
						handled = true
				KEY_PAGEUP, KEY_PAGEDOWN:
					if event.shift_pressed and wheel_size_controls.is_visible_in_tree():
						handled = _activate_button(wheel_size_controls.get_child(2 if event.keycode == KEY_PAGEUP else 0) as Button)
					elif event.shift_pressed and transmission_controls != null and transmission_controls.is_visible_in_tree():
						transmission_controls._height_selected(1 if event.keycode == KEY_PAGEUP else 0)
						handled = true
		if handled:
			consumed_shortcut_keys[event.keycode] = true
			get_viewport().set_input_as_handled()
			return
	# Consume both edges of global shortcuts so a
	# previously focused GUI button cannot also activate on the release.
	if event is InputEventKey and event.keycode in [KEY_F5, KEY_F9]:
		if event.pressed and not event.echo and not explanation_open:
			match event.keycode:
				KEY_F5:
					if not startup_save_pending:
						_save_worksite()
				KEY_F9: _load_worksite()
		get_viewport().set_input_as_handled()

func _activate_button(button: Button) -> bool:
	if button == null or not button.is_visible_in_tree() or button.disabled:
		return false
	button.pressed.emit()
	return true

func _open_action_menu(button: MenuButton) -> bool:
	if button == null or not button.is_visible_in_tree() or button.disabled:
		return false
	button.show_popup()
	return true

func _unhandled_input(event: InputEvent) -> void:
	if explanation_open or _object_menu_open() or _pause_menu_open() or _catalog_open():
		return
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_rotate_camera_from_mouse(event.relative)
		elif not component_nudge_active:
			hover_cell = _screen_cell(event.position)
			_update_cursor()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(0, distance - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(24, distance + 1)
			if distance > 0.0:
				orbit_pitch = maxf(orbit_pitch, 0.35)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var entity_id := _screen_entity(event.position)
			if mode == "deconstruct" or not _transmission_click(_transmission_center(event.position), entity_id):
				_world_click(_screen_cell(event.position), entity_id)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_8:
			building_hotbar.select_slot(event.keycode - KEY_1)
			get_viewport().set_input_as_handled()
			return
		match event.keycode:
			KEY_B: building_hotbar.open_catalog()
			KEY_PAGEUP:
				if mode != "component": _adjust_foundation_level(1)
			KEY_PAGEDOWN:
				if mode != "component": _adjust_foundation_level(-1)
			KEY_F: _select_tool("deconstruct" if _native_transmission() else "flow")
			KEY_C:
				if _native_transmission():
					_select_tool("flow")
			KEY_G: _select_tool("drive")
			KEY_E:
				if _native_transmission():
					_interact_pointed()
			KEY_R:
				if _native_transmission() and mode in ["collector", "processor", "wheel"]:
					_rotate_building()
				elif _native_transmission() and mode != "inspect":
					_cycle_placement_axis()
				else:
					_retrieve()
			KEY_H: _toggle_explanation()
			KEY_HOME: distance = 14.0
	_update_camera()

func _select_tool(tool: String) -> void:
	if explanation_open:
		return
	component_nudge_active = false
	component_nudge_center.clear()
	if transmission_controls != null:
		transmission_controls.cancel()
	mode = tool
	foundation_area_started = false
	pending_link = ""
	transmission_preview_point.clear()
	if _native_transmission() and transmission_controls != null:
		if tool == "wheel" and transmission_controls.selected_axis == "y":
			transmission_controls._axis_selected(0)
		if tool in ["gear", "drive", "belt", "gearbox", "vertical_gearbox", "chain_drive"]:
			transmission_controls.choose_tool({"gear": "gear", "drive": "place_shaft", "belt": "belt_span",
				"gearbox": "gearbox", "vertical_gearbox": "vertical_gearbox", "chain_drive": "chain_drive"}[tool])
	_update_cursor()
	_refresh_ui()
	var instructions := {"flow": "Click the upstream machine, then its neighbor toward the brass arrow.",
		"component": "Point at a part face to snap. Hold Alt and use arrows or Page Up / Down to nudge one quarter-grid step; click to place.",
		"pod_workshop": "Click a clear full tile to reinstall the carried pod workshop. It can sit on ground or a foundation top.",
		"drive": "Click two neighboring machines to connect a drive shaft.",
		"inspect": "E picks up pointed items or opens machines. Hold E at a placed crank." if _native_transmission() else "Click a machine to inspect it or collect its finished work.",
		"deconstruct": "Point at a built part and click to dismantle it. Escape leaves dismantle mode.",
		"collector": "Place the collector on the ore deposit.",
		"wheel": "Place the waterwheel in the flowing stream. Set its height to align its axle with your shafts."}
	if _native_transmission():
		instructions["collector"] = "Place the collector on ore-bearing ground, or on a foundation there at factory floor height."
		instructions["belt"] = "Choose two parallel shafts within reach. The belt runs across their axle, not along it."
		instructions["flow"] = "Choose the upstream machine, then its neighbor at the material outlet."
		instructions["drive"] = "Point at a floor to match its height, a part face to snap beside it, or a belt to add a pulley. Set the shaft axis in its menu."
		instructions["gear"] = "Point at a floor to match its height or a part face to snap beside it. Set the cogwheel axis in its menu."
		instructions["foundation"] = "Place a foundation at the displayed world height. Page Up / Page Down move one foundation thickness so stacked blocks touch; Access steps enables smaller walking steps. Machines need whole-tile factory floors. Area chooses two corners; Esc cancels."
		if tool == "component" and arrival_assembly_controls != null:
			var component_kind: String = arrival_assembly_controls.selected_name()
			if component_kind == "flat_head":
				instructions["component"] = "Aim at the anvil to show the head at press height. Click to fit it; the slide goes above."
			elif component_kind == "broad_anvil":
				instructions["component"] = "Aim at a clear 2×2 floor area. Click once to place four carried anvils as one workbed."
			elif component_kind == "broad_flat_head":
				instructions["component"] = "Aim at the 2×2 workbed. Click to fit four carried flat heads as one face."
			elif component_kind == "broad_copper_slide":
				instructions["component"] = "Aim at the 2×2 head. Click to fit four carried copper slides as one housing with a central piston."
			elif component_kind in ["wooden_slide", "copper_slide"]:
				instructions["component"] = "Aim at the anvil or flat head to show the slide at press height. Click to fit the amber ghost; red means blocked."
	_message(instructions.get(tool,
		"Place %s on an empty grid square." % NAMES.get(tool, tool)))

func _cancel_active_construction() -> bool:
	if mode == "inspect" and pending_link.is_empty() and not foundation_area_started \
			and not component_nudge_active \
			and transmission_preview_point.is_empty() \
			and (transmission_controls == null or transmission_controls.active_tool.is_empty()):
		return false
	component_preview_snap = ""
	component_preview_blocked = false
	component_preview_pose_key = ""
	component_preview_kind = ""
	foundation_area_start = Vector2i.ZERO
	_select_tool("inspect")
	return true

func _world_click(cell: Vector2i, entity_id: String = "") -> void:
	if explanation_open:
		return
	if mode == "deconstruct":
		var crank_id := _pointed_crank()
		if not crank_id.is_empty():
			issue({"action": "detach_hand_crank", "entity": crank_id})
			return
		var target := entity_id if _contains_target(state, entity_id) else ""
		if target.is_empty():
			_message("Point at a built part to dismantle it.", true)
			return
		var removal := "stow_fabrication_hub" if target == state.get("fabrication_hub", {}).get("id", "") else \
			"reclaim_component" if state.get("placed_components", {}).has(target) else \
			"remove_belt_span" if state.get("belt_spans", {}).has(target) else "remove"
		var outcome := issue({"action": removal, "entity": target})
		if outcome.accepted and selected == target:
			selected = ""
		_refresh_ui()
		return
	if mode == "pod_workshop" and _native_transmission():
		var hub: Dictionary = state.get("fabrication_hub", {})
		if hub.get("holder") != client or not _build_cell_allowed(cell):
			return
		var center := [cell.x * Geometry.HEIGHT_DENOMINATOR, _construction_level(cell),
			cell.y * Geometry.HEIGHT_DENOMINATOR]
		var outcome := issue({"action": "deploy_fabrication_hub", "entity": hub.id, "center": center})
		if outcome.accepted:
			selected = str(hub.id)
			_select_tool("inspect")
		return
	if mode == "component" and _native_transmission():
		if arrival_assembly_controls == null:
			return
		var center := _component_place_center(cell, entity_id)
		var component_name: String = arrival_assembly_controls.selected_name()
		if component_name == "hand_crank":
			var input_id := _rotary_at_input_port(center)
			if input_id.is_empty():
				_message("Point at a visible rotary input to place the crank.", true)
				return
			var carried_id := ""
			for item_id: String in state.get("crank_items", {}):
				if state.crank_items[item_id].get("holder", "") == client:
					carried_id = item_id
					break
			if carried_id.is_empty():
				_message("Craft and carry a hand crank before placing it at an input.", true)
				return
			var attach_wire := {"action": "attach_hand_crank", "entity": input_id,
				"crank": carried_id, "port": center}
			var crank_face := _crank_face_for_input(input_id, center)
			if crank_face.size() == 3:
				attach_wire["face"] = crank_face
			var attached := issue(attach_wire)
			if attached.accepted:
				selected = input_id
			_refresh_ui()
			return
		if not _component_area_bounds_allowed(component_name, center):
			return
		var selected_anvil: String = arrival_assembly_controls.press_anvil_for(selected)
		var outcome := issue({"action": "place_component",
			"component": component_name, "center": center})
		if outcome.accepted:
			selected = selected_anvil if component_name not in ["anvil", "broad_anvil"] and not selected_anvil.is_empty() \
				else str(outcome.get("entity", ""))
		_refresh_ui()
		return
	if _native_transmission():
		var height: int = transmission_controls.gear_height if transmission_controls != null else 0
		if _transmission_click([cell.x * 4, height, cell.y * 4], entity_id):
			return
		if mode == "belt":
			_message("Select the Belt tool and choose two parallel shafts.", true)
			return
		if mode == "inspect":
			if state.get("belt_spans", {}).has(entity_id):
				selected = entity_id
				_refresh_ui()
			return
	if mode != "foundation" and state.entities.has(entity_id):
		var actual: Array = state.entities[entity_id].cell
		cell = Vector2i(actual[0], actual[1])
	if not _build_cell_allowed(cell):
		return
	if mode == "inspect":
		selected = entity_id if not entity_id.is_empty() else _entity_at_cell(cell)
		_refresh_ui()
	elif mode in ["flow", "drive"]:
		var target := entity_id if not entity_id.is_empty() else _entity_at_cell(cell)
		if target.is_empty():
			_message("Choose a placed machine.", true)
			return
		selected = target
		if pending_link.is_empty():
			pending_link = target
			_message("Now choose the neighboring machine.")
		else:
			issue({"action": "connect" if mode == "flow" else "connect_drive", "from": pending_link, "to": target})
			pending_link = ""
	else:
		hover_cell = cell
		var action := {"action": "place", "kind": mode, "cell": [cell.x, cell.y]}
		if _native_transmission() and mode == "foundation":
			if foundation_area_mode:
				if not foundation_area_started:
					foundation_area_start = cell
					foundation_area_started = true
					_message("First corner chosen. Choose the opposite corner at this height; Esc cancels. The whole area uses carried parts.")
					return
				action = {"action": "place_foundations", "cell": [foundation_area_start.x, foundation_area_start.y], "end_cell": [cell.x, cell.y], "level": foundation_level}
				foundation_area_started = false
			else:
				action = {"action": "place_foundation", "cell": [cell.x, cell.y], "level": _construction_level(cell)}
		elif _native_transmission():
			action["level"] = _construction_level(cell)
			if mode == "wheel":
				action["tiles"] = wheel_tiles
		if _native_transmission() and transmission_controls != null:
			# Dot assignment creates a StringName key; the native wire deliberately
			# accepts only exact String dictionary keys, without coercion.
			if mode != "foundation":
				action["axis"] = ["x", "y", "z"][_preview_axis()]
		if _native_transmission() and mode in ["collector", "processor"]:
			action["rotation"] = building_rotation
		var outcome := issue(action)
		if outcome.accepted:
			selected = outcome.entity
	_refresh_ui()
	_update_cursor()

func _retrieve() -> void:
	var target := selected
	if target.is_empty() or not state.entities.has(target) or state.entities[target].kind != "processor":
		_message("Point at the press and press E, then collect its finished copper plate.", true)
		return
	issue({"action": "retrieve", "amount": 1, "entity": target})

func _pointed_screen_position() -> Vector2:
	return get_viewport().get_visible_rect().size * 0.5 if distance <= 0.0 else get_viewport().get_mouse_position()

func _pointed_crank() -> String:
	return _crank_at_screen(_pointed_screen_position())

func _crank_at_screen(screen: Vector2) -> String:
	var hit := _screen_pick(screen)
	if hit.is_empty():
		return ""
	var id: String = str(hit.collider.get_meta("crank_entity", ""))
	var item: Dictionary = state.get("crank_items", {}).get(id, {})
	return id if item.get("port", []).size() == 3 and str(item.get("holder", "")).is_empty() else ""

func _stop_held_crank() -> void:
	held_crank = ""
	held_crank_seconds = 0.0
	held_crank_context = ""
	held_crank_request = ""

func _settle_held_crank_request(request: String, accepted: bool) -> void:
	if request != held_crank_request:
		return
	if accepted:
		held_crank_request = ""
	else:
		_stop_held_crank()

func _advance_held_crank(delta: float) -> void:
	if held_crank.is_empty():
		return
	if not _crank_hold_allowed() or str(state.get("context", "")) != held_crank_context \
			or mode != "inspect" or _pointed_crank() != held_crank:
		_stop_held_crank()
		return
	held_crank_seconds = minf(STEP_SECONDS, held_crank_seconds + delta)
	if not held_crank_request.is_empty() or held_crank_seconds < STEP_SECONDS:
		return
	held_crank_seconds = 0.0
	var outcome := issue({"action": "operate_hand_crank", "entity": held_crank})
	if outcome.get("queued", false) and not str(outcome.get("request", "")).is_empty():
		held_crank_request = str(outcome.request)
	elif not outcome.get("accepted", false):
		_stop_held_crank()

func _crank_hold_allowed() -> bool:
	return DisplayServer.window_is_focused() and _can_control_character()

func _hand_source(id: String) -> Dictionary:
	var source: Variant = state.get("hand_sources", {}).get(id)
	if not source is Dictionary or source.get("kind") not in ["tree", "ore_deposit"] \
			or not Geometry.valid_position(source.get("position")) or typeof(source.get("remaining")) != TYPE_INT \
			or source.remaining < 0:
		return {}
	if source.has("contact_bounds"):
		var bounds: Variant = source.contact_bounds
		if not bounds is Array or bounds.size() != 2 or not Geometry.valid_position(bounds[0]) \
				or not Geometry.valid_position(bounds[1]):
			return {}
		for axis in range(3):
			if float(bounds[0][axis]) >= float(bounds[1][axis]):
				return {}
	return source

func _hand_source_in_reach(source: Dictionary) -> bool:
	var actor: Dictionary = state.get("actors", {}).get(client, {})
	var position: Variant = actor.get("position")
	var radius: Variant = actor.get("capabilities", {}).get("harvest_reach")
	if not Geometry.valid_position(position) or not (radius is float or radius is int) or radius <= 0:
		return false
	var target: Array = source.position.duplicate()
	if source.has("contact_bounds"):
		var bounds: Array = source.contact_bounds
		for axis in range(3):
			target[axis] = clampf(float(position[axis]), float(bounds[0][axis]), float(bounds[1][axis]))
	var distance_squared := 0.0
	for axis in range(3):
		var difference: float = float(position[axis]) - float(target[axis])
		distance_squared += difference * difference
	return distance_squared <= float(radius) * float(radius)

func _hand_source_clear(id: String) -> bool:
	var actor: Dictionary = state.get("actors", {}).get(client, {})
	return actor.get("harvest_clear", {}).get(id, true) == true

func _field_source_at(at: Vector3) -> String:
	var deposit: Dictionary = state.get("source_deposit", {})
	if deposit.get("cells", []).size() < 100:
		return ""
	var prefix := str(deposit.get("id", "")) + "-region-"
	for id: String in state.get("hand_sources", {}):
		if not id.begins_with(prefix):
			continue
		var source := _hand_source(id)
		if source.is_empty() or not source.has("contact_bounds"):
			continue
		var bounds: Array = source.contact_bounds
		if at.x >= float(bounds[0][0]) and at.x <= float(bounds[1][0]) \
				and at.z >= float(bounds[0][2]) and at.z <= float(bounds[1][2]):
			return id
	return ""

func _refresh_ore_field() -> void:
	var deposit: Dictionary = state.get("source_deposit", {})
	var scenery := get_node_or_null("ProductionScenery")
	if scenery == null:
		return
	var key := str(deposit.get("cells", []).size())
	for id: String in state.get("hand_sources", {}):
		if id.begins_with(str(deposit.get("id", "")) + "-region-"):
			key += ":" + id + "=" + str(state.hand_sources[id].get("remaining", -1))
	if key == ore_field_visual_key:
		return
	ore_field_visual_key = key
	if ore_field_visual != null:
		ore_field_visual.queue_free()
		ore_field_visual = null
	ore_field_visual = ProductionEnvironment.ore_field(state)
	if ore_field_visual != null:
		scenery.add_child(ore_field_visual)

func _prepare_hand_tree_assets() -> bool:
	if not hand_tree_assets.is_empty():
		return true
	var loaded := ProductionEnvironment.read_pine()
	if loaded.status != "ready":
		push_error("Harvestable trees require the qualified pine mesh.")
		return false
	var mesh: ArrayMesh = loaded.mesh
	var bark_surface := -1
	for surface in range(mesh.get_surface_count()):
		var material := mesh.surface_get_material(surface) as StandardMaterial3D
		if material != null and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			bark_surface = surface
			break
	if bark_surface < 0:
		push_error("The harvestable pine has no opaque bark surface.")
		return false
	var arrays := mesh.surface_get_arrays(bark_surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var base_height := mesh.get_aabb().position.y
	var root_min := Vector3(INF, base_height, INF)
	var root_max := Vector3(-INF, base_height, -INF)
	for point in vertices:
		if point.y <= base_height + 0.025:
			root_min = root_min.min(point)
			root_max = root_max.max(point)
	if not root_min.is_finite() or not root_max.is_finite():
		push_error("The harvestable pine has no grounded bark root.")
		return false
	var root := Vector3((root_min.x + root_max.x) * 0.5, base_height, (root_min.z + root_max.z) * 0.5)
	var radius := maxf(root_max.x - root_min.x, root_max.z - root_min.z) * 0.5
	var faces := PackedVector3Array()
	for index in indices:
		faces.append(vertices[index] - root)
	var trunk := ConcavePolygonShape3D.new()
	trunk.backface_collision = true
	trunk.set_faces(faces)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("68503b")
	wood.roughness = 1.0
	wood.metallic_specular = 0.0
	wood.cull_mode = BaseMaterial3D.CULL_DISABLED
	var base := _hand_tree_stump(arrays, root, mesh.surface_get_material(bark_surface), wood)
	if base.is_empty():
		return false
	# The scar follows every actual bark face. A single tiny quad could face
	# away from the worker after the tree's deterministic rotation.
	var scar_arrays: Array = arrays.duplicate(true)
	var scar_vertices := PackedVector3Array()
	for point in vertices:
		scar_vertices.append(point - root)
	scar_arrays[Mesh.ARRAY_VERTEX] = scar_vertices
	var scar := ArrayMesh.new()
	scar.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, scar_arrays)
	var scar_shader := Shader.new()
	scar_shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform float cut_fraction : hint_range(0.0, 1.0) = 0.125;
varying vec3 bark;
void vertex() {
	bark = VERTEX;
	VERTEX += NORMAL * 0.0006;
}
void fragment() {
	float angle = atan(bark.z, bark.x);
	float rough_edge = sin(angle * 5.0 + 2.0) * 0.002 + sin(angle * 11.0) * 0.001;
	float half_height = mix(0.006, 0.026, cut_fraction) * (0.8 + 0.2 * sin(angle * 3.0));
	float edge = abs(bark.y - 0.18 - rough_edge) / half_height;
	if (edge > 1.0) { discard; }
	float grain = 0.9 + 0.1 * sin(bark.x * 2200.0 + bark.z * 1700.0 + sin(bark.y * 75.0));
	ALBEDO = mix(vec3(0.43, 0.30, 0.19) * grain, vec3(0.23, 0.14, 0.07), smoothstep(0.7, 1.0, edge));
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
"""
	var scar_material := ShaderMaterial.new()
	scar_material.shader = scar_shader
	scar.surface_set_material(0, scar_material)
	var stump_shape := CylinderShape3D.new()
	stump_shape.height = base.height
	stump_shape.radius = radius
	hand_tree_assets = {"mesh": mesh, "root": root, "trunk": trunk, "stump": base.mesh,
		"stump_shape": stump_shape, "stump_height": base.height, "cut": base.cap, "notch": scar}
	return true

func _hand_tree_stump(arrays: Array, root: Vector3, bark: Material, wood: Material) -> Dictionary:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var sides := SurfaceTool.new()
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim: Array[Vector3] = []
	# Clip the qualified trunk rather than substituting a lathed post. The
	# shallow sloping cut preserves its flare, lean, texture and irregular rim.
	for first in range(0, indices.size(), 3):
		var polygon: Array[Dictionary] = []
		for index in indices.slice(first, first + 3):
			polygon.append({"p": vertices[index] - root, "n": normals[index], "uv": uv[index]})
		var clipped: Array[Dictionary] = []
		for i in range(3):
			var a: Dictionary = polygon[i]
			var b: Dictionary = polygon[(i + 1) % 3]
			var da: float = a.p.y - 0.045 - a.p.x * 0.15 - a.p.z * 0.10
			var db: float = b.p.y - 0.045 - b.p.x * 0.15 - b.p.z * 0.10
			if da <= 0.0:
				clipped.append(a)
			if (da <= 0.0) != (db <= 0.0):
				var t := da / (da - db)
				var point: Vector3 = a.p.lerp(b.p, t)
				clipped.append({"p": point, "n": a.n.lerp(b.n, t).normalized(), "uv": a.uv.lerp(b.uv, t)})
				var unique := true
				for existing in rim:
					if existing.distance_squared_to(point) < 0.0000000001:
						unique = false
						break
				if unique:
					rim.append(point)
		for i in range(1, clipped.size() - 1):
			for point: Dictionary in [clipped[0], clipped[i], clipped[i + 1]]:
				sides.set_normal(point.n)
				sides.set_uv(point.uv)
				sides.add_vertex(point.p)
	if rim.size() < 3:
		push_error("The qualified pine has no closed stump section.")
		return {}
	var center := Vector3.ZERO
	var height := 0.0
	for point in rim:
		center += point
		height = maxf(height, point.y)
	center /= float(rim.size())
	rim.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return atan2(a.z - center.z, a.x - center.x) < atan2(b.z - center.z, b.x - center.x))
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(rim.size()):
		for point: Vector3 in [center, rim[i], rim[(i + 1) % rim.size()]]:
			top.set_normal(Vector3(-0.15, 1.0, -0.10).normalized())
			top.add_vertex(point)
	var stump := sides.commit()
	stump.surface_set_material(0, bark)
	var cap := top.commit()
	cap.surface_set_material(0, wood)
	return {"mesh": stump, "cap": cap, "height": height}

func _refresh_hand_trees() -> void:
	var sources := {}
	if _native_transmission() and ProductionEnvironment.Surface != null:
		for id: String in state.get("hand_sources", {}):
			var source := _hand_source(id)
			if source.get("kind") == "tree" and typeof(source.get("initial")) == TYPE_INT \
					and source.initial > 0 and source.remaining <= source.initial:
				sources[id] = source
	_refresh_mature_trees(sources)
	for id: String in hand_tree_nodes.keys():
		if not sources.has(id) or hand_tree_nodes[id].get_meta("source_position") != sources[id].position:
			hand_tree_nodes[id].free()
			hand_tree_nodes.erase(id)
	if sources.is_empty() or not _prepare_hand_tree_assets():
		return
	for id: String in sources:
		if id.begins_with("fir_") or id.begins_with("broadleaf_"):
			continue
		var source: Dictionary = sources[id]
		if not hand_tree_nodes.has(id):
			var body := StaticBody3D.new()
			body.collision_layer = Geometry.PICK_LAYER
			body.collision_mask = 0
			body.set_meta("hand_source", id)
			body.set_meta("source_position", source.position.duplicate())
			body.position = Vector3(source.position[0], 0.0, source.position[2])
			body.position.y = ProductionEnvironment.Surface.height_at(body.position.x, body.position.z)
			var variation := absi(id.hash())
			body.basis = Basis(Vector3.UP, deg_to_rad(float(variation % 360))).scaled_local(Vector3.ONE * (4.0 + float(variation % 3) * 0.3))
			var tree := MeshInstance3D.new()
			tree.name = "Tree"
			tree.mesh = hand_tree_assets.mesh
			tree.position = -hand_tree_assets.root
			tree.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
			body.add_child(tree)
			var stump := MeshInstance3D.new()
			stump.name = "Stump"
			stump.mesh = hand_tree_assets.stump
			body.add_child(stump)
			var cut := MeshInstance3D.new()
			cut.name = "Cut"
			cut.mesh = hand_tree_assets.cut
			body.add_child(cut)
			var picker := CollisionShape3D.new()
			picker.name = "PickShape"
			body.add_child(picker)
			add_child(body)
			hand_tree_nodes[id] = body
		var body: StaticBody3D = hand_tree_nodes[id]
		var counts := [source.initial, source.remaining]
		if body.get_meta("presented_counts", []) == counts:
			continue
		body.set_meta("presented_counts", counts)
		var standing: bool = source.remaining > 0
		body.get_node("Tree").visible = standing
		body.get_node("Stump").visible = not standing
		var picker: CollisionShape3D = body.get_node("PickShape")
		var shape: Shape3D = hand_tree_assets.trunk if standing else hand_tree_assets.stump_shape
		if picker.shape != shape:
			picker.shape = shape
		picker.position.y = 0.0 if standing else hand_tree_assets.stump_height * 0.5
		var cut: MeshInstance3D = body.get_node("Cut")
		cut.visible = source.remaining < source.initial
		cut.mesh = hand_tree_assets.notch if standing else hand_tree_assets.cut
		cut.transform = Transform3D.IDENTITY
		var fraction := 1.0 - float(source.remaining) / float(source.initial)
		if standing and cut.visible:
			if cut.material_override == null:
				cut.material_override = hand_tree_assets.notch.surface_get_material(0).duplicate()
			cut.material_override.set_shader_parameter("cut_fraction", fraction)
		else:
			cut.material_override = null

func _mature_cut_disk(radius: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in range(48):
		var angle := TAU * float(segment) / 48.0
		var next_angle := TAU * float(segment + 1) / 48.0
		var edge := radius * (1.0 + 0.025 * sin(angle * 5.0) + 0.012 * sin(angle * 11.0))
		var next_edge := radius * (1.0 + 0.025 * sin(next_angle * 5.0)
			+ 0.012 * sin(next_angle * 11.0))
		var first := Vector2(cos(angle), sin(angle)) * edge
		var second := Vector2(cos(next_angle), sin(next_angle)) * next_edge
		for point in [Vector2.ZERO, first, second]:
			tool.set_normal(Vector3.UP)
			tool.set_uv(Vector2(0.5 + point.x / (2.0 * radius),
				0.5 + point.y / (2.0 * radius)))
			tool.add_vertex(Vector3(point.x, 0.0, point.y))
	return tool.commit()

func _refresh_mature_trees(sources: Dictionary) -> void:
	var scenery := get_node_or_null("ProductionScenery")
	if scenery == null or ProductionEnvironment.Surface == null:
		return
	if mature_tree_collision_rows.is_empty():
		for row in ProductionEnvironment.Surface.mature_tree_collision_rows():
			mature_tree_collision_rows[row.id] = row
	for spec in ProductionEnvironment.Surface.fir_specs() + ProductionEnvironment.Surface.broadleaf_specs():
		var id: String = spec.id
		var group := "BankFirs" if id.begins_with("fir_") else "BankBroadleaf"
		var standing_mesh := scenery.get_node_or_null("%s/%s" % [group, id]) as MeshInstance3D
		if standing_mesh == null:
			continue
		var source: Dictionary = sources.get(id, {})
		var center: Vector3 = spec.center
		var site := Vector3(float(source.get("position", [0.0, 0.0, 0.0])[0]), 0.0,
			float(source.get("position", [0.0, 0.0, 0.0])[2]))
		if source.is_empty() or Vector2(site.x - center.x, site.z - center.z).length() > 0.35:
			standing_mesh.visible = false
			push_error("Mature tree lacks a matching native timber source: " + id)
			continue
		var standing: bool = source.remaining > 0
		standing_mesh.visible = standing
		if not mature_tree_nodes.has(id):
			var body := StaticBody3D.new()
			body.name = "MatureTreePicker_" + id
			body.collision_layer = Geometry.PICK_LAYER
			body.collision_mask = 0
			body.set_meta("hand_source", id)
			var picker := CollisionShape3D.new()
			picker.name = "PickShape"
			body.add_child(picker)
			var radius := 0.28 if id.begins_with("fir_") else 0.5
			var stump := MeshInstance3D.new()
			stump.name = "Stump"
			var stump_mesh := CylinderMesh.new()
			stump_mesh.height = 0.18
			stump_mesh.bottom_radius = radius
			stump_mesh.top_radius = radius * 0.9
			stump.mesh = stump_mesh
			stump.material_override = standing_mesh.mesh.surface_get_material(2)
			stump.position = Vector3(center.x,
				ProductionEnvironment.Surface.height_at(center.x, center.z) + 0.07, center.z)
			body.add_child(stump)
			var cap := MeshInstance3D.new()
			cap.name = "CutFace"
			cap.mesh = _mature_cut_disk(radius * 0.9)
			cap.material_override = ProductionEnvironment.cut_wood_material()
			cap.position = stump.position + Vector3.UP * 0.11
			body.add_child(cap)
			add_child(body)
			mature_tree_nodes[id] = body
		var body: StaticBody3D = mature_tree_nodes[id]
		if body.has_meta("standing") and body.get_meta("standing") == standing:
			continue
		body.set_meta("standing", standing)
		body.get_node("Stump").visible = not standing
		body.get_node("CutFace").visible = not standing
		var picker: CollisionShape3D = body.get_node("PickShape")
		if standing:
			var shape := ConcavePolygonShape3D.new()
			shape.backface_collision = true
			shape.set_faces(mature_tree_collision_rows[id].faces)
			picker.position = Vector3.ZERO
			picker.shape = shape
		else:
			var shape := CylinderShape3D.new()
			shape.radius = 0.28 if id.begins_with("fir_") else 0.5
			shape.height = 0.18
			picker.position = body.get_node("Stump").position
			picker.shape = shape

func _screen_hand_source(screen: Vector2) -> String:
	if not _native_transmission() or camera == null or state.get("hand_sources", {}).is_empty():
		return ""
	var eye := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(eye, eye + camera.project_ray_normal(screen) * 80.0,
		Geometry.GROUND_LAYER | Geometry.MACHINE_LAYER | Geometry.PICK_LAYER | TRANSMISSION_TERRAIN_PICK_LAYER)
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return ""
	# A resource presenter identifies the actual hit, rather than selecting a
	# nearby source from camera distance. Host retains the actor-reach check.
	var id: String = str(hit.collider.get_meta("hand_source", ""))
	if id.is_empty() and actor_world != null and hit.collider == actor_world.floor_body:
		id = _field_source_at(hit.position)
	if id.is_empty() and actor_world != null and hit.collider == actor_world.floor_body:
		# Standing mature trunks use the same exact triangles in the actor floor
		# and in a resource picker. Resolve the coincident hit by its pick ID,
		# but keep a nearer terrain surface as an occluder.
		var pick_query := PhysicsRayQueryParameters3D.create(eye,
			eye + camera.project_ray_normal(screen) * 80.0, Geometry.PICK_LAYER)
		var pick := get_world_3d().direct_space_state.intersect_ray(pick_query)
		if not pick.is_empty() and pick.collider.get_meta("hand_source", "") != "" \
				and pick.position.distance_to(eye) <= hit.position.distance_to(eye) + 0.03:
			id = str(pick.collider.get_meta("hand_source"))
	if id.is_empty() and hit.collider == get_node_or_null("SharedOreSourcePicker"):
		# The shared view owns only a pick shape. The server projection supplies
		# the source identity and remains the sole stock and reach authority.
		id = _field_source_at(hit.position)
		if id.is_empty():
			id = str(state.get("source_deposit", {}).get("id", ""))
	if id.is_empty() and actor_world != null and hit.collider == actor_world.site_bodies.get("source_outcrop"):
		id = _field_source_at(hit.position)
	if id.is_empty() and actor_world != null and hit.collider == actor_world.site_bodies.get("source_outcrop"):
		var deposits: Array[String] = []
		for key: String in state.hand_sources:
			if _hand_source(key).get("kind") == "ore_deposit":
				deposits.append(key)
		if deposits.size() == 1:
			id = deposits[0]
	return id if not _hand_source(id).is_empty() else ""

func _screen_loose_material(screen: Vector2) -> Dictionary:
	if not _native_transmission() or camera == null or not camera.is_inside_tree():
		return {}
	var eye := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(eye,
		eye + camera.project_ray_normal(screen) * 80.0,
		Geometry.GROUND_LAYER | Geometry.MACHINE_LAYER | Geometry.PICK_LAYER | TRANSMISSION_TERRAIN_PICK_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.collider.get_meta("material_context", "") != state.get("context", ""):
		return {}
	var drop: Dictionary = hit.collider.get_meta("loose_material", {})
	# A stale visible body must never collect a replacement at the same location.
	return drop if not drop.is_empty() and state.get("dropped_material", []).has(drop) else {}

func _interact_pointed() -> void:
	if not _can_control_character():
		return
	var drop := _screen_loose_material(_pointed_screen_position()) if mode == "inspect" else {}
	if not drop.is_empty():
		var expected: Dictionary = drop.duplicate(true)
		expected.erase("center")
		issue({"action": "pickup_material", "center": drop.center.duplicate(), "expected": expected})
		return
	var pointed_crank := _pointed_crank() if mode == "inspect" else ""
	if not pointed_crank.is_empty():
		if str(state.get("crank_items", {}).get(pointed_crank, {}).get("attached_to", "")).is_empty():
			_message("This crank has no connected shaft. Reclaim it with F, then click.", true)
			return
		held_crank = pointed_crank
		held_crank_context = str(state.get("context", ""))
		held_crank_request = ""
		held_crank_seconds = STEP_SECONDS
		_advance_held_crank(0.0)
		return
	var source_id := _screen_hand_source(_pointed_screen_position()) if mode == "inspect" else ""
	var source := _hand_source(source_id)
	if source.is_empty():
		_open_pointed_machine()
		return
	if not _placement_ready():
		return
	if source.remaining == 0:
		_message("This source is depleted. Choose another tree or ore deposit.", true)
		return
	if not _hand_source_in_reach(source):
		_message("Move closer to the source before harvesting.", true)
		return
	if not _hand_source_clear(source_id):
		_message("Move around the obstacle before harvesting.", true)
		return
	if state.get("manual_cuts", {}).has(client):
		return
	issue({"action": "harvest_source", "target": source_id})

func _open_pointed_machine() -> void:
	if _catalog_open() or not _can_control_character():
		return
	var target := _screen_entity(_pointed_screen_position())
	if not _contains_target(state, target):
		_message("Point at a machine or part and press E to open it.", true)
		return
	_open_object_menu_for(target)

func _open_object_menu_for(target: String) -> void:
	if not _contains_target(state, target):
		return
	if building_hotbar != null and building_hotbar._valid_bench(state, target):
		_select_tool("inspect")
		selected = target
		_refresh_ui()
		building_hotbar.open_at_bench(target)
		return
	_select_tool("inspect")
	selected = target
	_refresh_ui()
	if arrival_assembly_controls != null:
		arrival_assembly_controls.open_context()
	object_menu_target = target
	object_menu_title.text = _object_name(target)
	object_menu_operations_label.text = "PART ACTIONS"
	var active_press := _is_guided_press_part(target)
	if active_press:
		object_menu_operations_label.text = "PRESS WORK"
	for row: Variant in state.get("collector_assemblies", []):
		if row is Dictionary and row.get("parts", {}).get("frame", "") == target:
			object_menu_operations_label.text = "COLLECTOR"
	object_menu_operations.visible = _object_supports_operations(target) and arrival_assembly_scroll.visible
	_release_character_controls()
	object_menu_scrim.visible = true
	var compact_collector := _is_collector_frame(target)
	var compact_part: bool = state.get("placed_components", {}).has(target) and not active_press and not compact_collector
	if compact_collector:
		arrival_assembly_scroll.custom_minimum_size.y = 0
	object_menu_desired_extent = Vector2i(620 if compact_part else 760 if object_menu_operations.visible else 500,
		280 if compact_part else 400 if compact_collector else 520 if object_menu_operations.visible else 400)
	var extent := _object_menu_extent()
	object_menu.min_size = extent
	object_menu.popup_centered(extent)
	_fit_object_menu()
	object_menu_close.grab_focus()
	_refresh_ui()

func _object_menu_extent(viewport: Vector2i = Vector2i.ZERO) -> Vector2i:
	if viewport == Vector2i.ZERO:
		viewport = Vector2i(get_viewport().get_visible_rect().size)
	return Vector2i(mini(object_menu_desired_extent.x, maxi(320, viewport.x - 24)),
		mini(object_menu_desired_extent.y, maxi(280, viewport.y - 24)))

func _fit_object_menu(viewport: Vector2i = Vector2i.ZERO) -> void:
	if viewport == Vector2i.ZERO:
		viewport = Vector2i(get_viewport().get_visible_rect().size)
	var narrow := viewport.x < 800
	object_menu_detail_panel.custom_minimum_size.x = 180 if narrow else 220
	object_menu_operations.custom_minimum_size.x = 340 if narrow else 420
	arrival_assembly_controls.custom_minimum_size.x = 340 if narrow else 410
	var extent := _object_menu_extent(viewport)
	object_menu.min_size = extent
	object_menu.size = extent
	object_menu.position = (viewport - object_menu.size) / 2
	object_menu_viewport_size = viewport

func _remove_selected() -> void:
	if not selected.is_empty():
		var removal := "stow_fabrication_hub" if selected == state.get("fabrication_hub", {}).get("id", "") else \
			"reclaim_component" if state.get("placed_components", {}).has(selected) else \
			"remove_belt_span" if _native_transmission() and state.get("belt_spans", {}).has(selected) else "remove"
		var outcome := issue({"action": removal, "entity": selected})
		if outcome.accepted:
			selected = ""
			if _object_menu_open():
				object_menu.hide()
			_refresh_ui()

func _toggle_explanation() -> void:
	explanation_open = not explanation_open
	help_panel.visible = explanation_open
	if explanation_open:
		_release_character_controls()
		help_title.text = objective_title
		help_body.text = _help_goal_text()
	_update_cursor()
	_refresh_ui()

func _help_goal_text() -> String:
	var detail := "\n\n" + goal_detail if not goal_detail.is_empty() else ""
	return goal_text + detail + "\n\n" + controls_label.text

func _screen_cell(screen: Vector2) -> Vector2i:
	if _native_transmission() and mode != "foundation":
		var id := _screen_entity(screen)
		var surface: Dictionary = state.get("foundations", {}).get(id, state.get("entities", {}).get(id, {}))
		if not surface.is_empty():
			return Vector2i(surface.cell[0], surface.cell[1])
	# Select a requested construction datum, not permission or terrain contact.
	# Shared clients need no duplicate ground collider. The host decides actual
	# placement; an area request deliberately has no construction reach limit.
	var height := foundation_level * Geometry.HEIGHT_STEP if _native_transmission() and mode == "foundation" else 0.0
	var point = Plane(Vector3.UP, height).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if point == null:
		return Vector2i(999999, 999999)
	return Vector2i(roundi(point.x / PITCH), roundi(point.z / PITCH))

func _screen_entity(screen: Vector2) -> String:
	return _picked_target_id(_screen_pick(screen))

func _picked_target_id(hit: Dictionary) -> String:
	if hit.is_empty():
		return ""
	var collider: Object = hit.collider
	for key in ["entity", "component_entity", "transmission"]:
		var id: String = str(collider.get_meta(key, ""))
		if not id.is_empty():
			return id
	return ""

func _component_pointed_center() -> Array:
	var screen := _pointed_screen_position()
	return _component_place_center(_screen_cell(screen), _screen_entity(screen), false)

func _rotary_at_input_port(port: Array) -> String:
	var found := ""
	for id: String in state.get("placed_components", {}):
		var placed: Dictionary = state.placed_components[id]
		if placed.get("input_ports", []).has(port):
			if not found.is_empty():
				return ""
			found = id
	return found

func _crank_face_for_input(input_id: String, port: Array) -> Array:
	var input: Dictionary = state.get("placed_components", {}).get(input_id, {})
	var center: Array = input.get("center", [])
	if center.size() != 3 or port.size() != 3:
		return []
	if center != port:
		return [1 if int(port[0]) > int(center[0]) else -1, 0, 0]
	var axis := int(input.get("crank_axis", -1))
	var actor: Dictionary = state.get("actors", {}).get(client, {})
	var position: Array = actor.get("position", [])
	var anchor_position: Array = input.get("position", [])
	if axis not in [0, 2] or position.size() != 3 or anchor_position.size() != 3:
		return []
	var face := [0, 0, 0]
	face[axis] = -1 if float(position[axis]) < float(anchor_position[axis]) else 1
	return face

func _guided_press_part_snap(kind: String, pointed_kind: String, center: Array,
		normal: Vector3) -> Dictionary:
	# The press's working offsets are larger than a one-step face snap. Use the
	# part the player can actually point at to expose its next fitted socket.
	if kind == "flat_head" and pointed_kind == "anvil":
		return {"center": [center[0], center[1] + 1, center[2]], "label": "Head over workbed"}
	if kind in ["wooden_slide", "copper_slide"] and pointed_kind == "anvil":
		return {"center": [center[0], center[1] + 2, center[2]], "label": "Slide over workbed"}
	if kind == "broad_flat_head" and pointed_kind == "broad_anvil":
		return {"center": [center[0], center[1] + 1, center[2]], "label": "2×2 head over workbed"}
	if kind in ["wooden_slide", "copper_slide"] and pointed_kind == "flat_head":
		return {"center": [center[0], center[1] + 1, center[2]], "label": "Slide over head"}
	if kind in ["wooden_slide", "copper_slide"] and pointed_kind == "broad_flat_head":
		return {}
	if kind == "broad_copper_slide" and pointed_kind == "broad_flat_head":
		return {"center": [center[0], center[1] + 3, center[2]],
			"label": "2×2 housing over broad head"}
	if kind == "ram_face" and pointed_kind == "anvil":
		return {"center": [center[0], center[1] + 1, center[2]], "label": "Ram over anvil"}
	if kind == "sliding_guide" and pointed_kind in ["anvil", "ram_face"]:
		var rise := 3 if pointed_kind == "anvil" else 2
		return {"center": [center[0], center[1] + rise, center[2]],
			"label": "Guide over %s" % ("ram" if pointed_kind == "ram_face" else "anvil")}
	if pointed_kind == "anvil" and kind in ["wooden_shaft", "copper_shaft",
			"wooden_cog", "copper_cog"]:
		var distance := 1 if kind in ["wooden_shaft", "copper_shaft"] else 2
		if absf(normal.x) > 0.5 and absf(normal.x) > absf(normal.z):
			return {"center": [center[0] + distance * (1 if normal.x > 0.0 else -1),
				center[1] + 4, center[2]], "label": "Press drive from anvil"}
		if absf(normal.z) > 0.5:
			return {"center": [center[0], center[1] + 4,
				center[2] + distance * (1 if normal.z > 0.0 else -1)],
				"label": "Press drive from anvil"}
	if kind in ["wooden_shaft", "copper_shaft"] and pointed_kind == "sliding_guide":
		if absf(normal.x) > 0.5 and absf(normal.x) > absf(normal.z):
			return {"center": [center[0] + (1 if normal.x > 0.0 else -1),
				center[1] + 1, center[2]], "label": "Drive beside guide"}
		if absf(normal.z) > 0.5:
			return {"center": [center[0], center[1] + 1,
				center[2] + (1 if normal.z > 0.0 else -1)], "label": "Drive beside guide"}
	return {}

func _component_place_center(cell: Vector2i, pointed: String, use_nudge := true) -> Array:
	# One quarter-grid step off a confirmed component face builds a stack or
	# lateral drive. Host still decides support, occupancy, custody and reach.
	if use_nudge and component_nudge_active and component_nudge_center.size() == 3:
		return component_nudge_center.duplicate()
	if arrival_assembly_controls != null and arrival_assembly_controls.selected_name() == "wooden_workbench":
		return [cell.x * Geometry.HEIGHT_DENOMINATOR, _construction_level(cell),
			cell.y * Geometry.HEIGHT_DENOMINATOR]
	var placed: Dictionary = state.get("placed_components", {})
	if placed.has(pointed):
		var hit := _screen_pick(_pointed_screen_position())
		if not hit.is_empty() and hit.collider.get_meta("component_entity", "") == pointed:
			var normal: Vector3 = hit.normal
			var center: Array = placed[pointed].center.duplicate()
			var kind: String = arrival_assembly_controls.selected_name() if arrival_assembly_controls != null else ""
			if kind == "hand_crank" and placed[pointed].get("component", "") in \
					["tool_mount", "wooden_shaft", "copper_shaft"]:
				return center
			if kind == "flat_head" and str(placed[pointed].component) in ["wooden_slide", "copper_slide"]:
				return [center[0], center[1] - 1, center[2]]
			var press_snap := _guided_press_part_snap(kind, str(placed[pointed].component), center, normal)
			if not press_snap.is_empty():
				return press_snap.center
			var axis := 0
			if absf(normal.y) > absf(normal.x) and absf(normal.y) >= absf(normal.z):
				axis = 1
			elif absf(normal.z) > absf(normal.x):
				axis = 2
			var stride := Geometry.HEIGHT_DENOMINATOR if axis != 1 and kind in [
					"anvil", "flat_head", "wooden_slide", "copper_slide"] else 1
			center[axis] += stride if normal[axis] >= 0.0 else -stride
			return center
	return [cell.x * Geometry.HEIGHT_DENOMINATOR,
		_construction_level(cell), cell.y * Geometry.HEIGHT_DENOMINATOR]

func _component_center_allowed(center: Array) -> bool:
	if center.size() != 3 or ProductionEnvironment.Surface == null:
		return false
	var half: float = ProductionEnvironment.Surface.HALF - Geometry.HEIGHT_STEP / 2.0
	return absf(center[0] * Geometry.HEIGHT_STEP) <= half \
		and absf(center[2] * Geometry.HEIGHT_STEP) <= half

func _component_area_bounds_allowed(kind: String, center: Array) -> bool:
	if not _component_center_allowed(center):
		return false
	if kind == "anvil" and (
			int(center[0]) % Geometry.HEIGHT_DENOMINATOR != 0 or
			int(center[2]) % Geometry.HEIGHT_DENOMINATOR != 0):
		return false
	if kind not in ["anvil", "flat_head", "wooden_slide", "copper_slide",
			"broad_anvil", "broad_flat_head", "broad_copper_slide"]:
		return true
	var box := _component_candidate_box(kind, center)
	return absf(box.center.x) + box.half.x <= ProductionEnvironment.Surface.HALF \
		and absf(box.center.z) + box.half.z <= ProductionEnvironment.Surface.HALF

func _toggle_component_footprint() -> void:
	if mode != "component" or arrival_assembly_controls == null \
			or arrival_assembly_controls.selected_name() not in [
				"anvil", "broad_anvil", "flat_head", "broad_flat_head",
				"copper_slide", "broad_copper_slide"]:
		return
	var next_kind: String = {
		"anvil": "broad_anvil", "broad_anvil": "anvil",
		"flat_head": "broad_flat_head", "broad_flat_head": "flat_head",
		"copper_slide": "broad_copper_slide", "broad_copper_slide": "copper_slide",
	}[arrival_assembly_controls.selected_name()]
	if not arrival_assembly_controls.select_component_name(next_kind):
		return
	component_preview_pose_key = ""
	_refresh_component_preview()
	_update_cursor()
	if building_hotbar != null:
		building_hotbar.refresh()

func _component_collector_face(kind: String, center: Array) -> Dictionary:
	if kind not in ["tool_mount", "cutting_edge"]:
		return {}
	var step := 1 if kind == "tool_mount" else 2
	for face: Dictionary in state.get("collector_assemblies", []):
		var machine: Variant = face.get("center")
		var toward: Variant = face.get("toward_ore")
		if machine is Array and machine.size() == 3 and toward is Array and toward.size() == 3 \
				and center[0] == machine[0] + step * toward[0] \
				and center[1] in [machine[1], machine[1] + 1] \
				and center[2] == machine[2] + step * toward[2]:
			return face
	return {}

func _component_candidate_box(kind: String, center: Array) -> Dictionary:
	var at := Vector3(center[0] * Geometry.HEIGHT_STEP,
		center[1] * Geometry.HEIGHT_STEP + Geometry.ANCHOR_HEIGHT,
		center[2] * Geometry.HEIGHT_STEP)
	var occupied := at
	var half := Vector3(0.14, 0.14, 0.14)
	var collector_face := _component_collector_face(kind, center)
	if not collector_face.is_empty():
		var floor_y: float = collector_face.center[1] * Geometry.HEIGHT_STEP
		var top_y: float = at.y + (0.28 if kind == "tool_mount" else 0.105)
		var along_x: bool = collector_face.toward_ore[0] != 0
		var face_half := 0.21 if kind == "tool_mount" else 0.2025
		occupied.y = (floor_y + top_y) * 0.5
		half = Vector3(face_half if along_x else (0.20 if kind == "tool_mount" else 0.21),
			(top_y - floor_y) * 0.5,
			(0.19 if kind == "tool_mount" else 0.18) if along_x else face_half)
		return {"center": occupied, "half": half, "size": half * 2.0}
	match kind:
		"wooden_frame":
			occupied.y = center[1] * Geometry.HEIGHT_STEP + 0.45
			half = Vector3(0.2025, 0.45, 0.2025)
		"wooden_workbench":
			occupied.y = center[1] * Geometry.HEIGHT_STEP + 0.45
			half = Vector3(0.34, 0.45, 0.30)
		"channel_narrow_x", "channel_narrow_z", "channel_broad_x", "channel_broad_z":
			var pitch := Geometry.HEIGHT_STEP * 4.0
			var wide := kind.begins_with("channel_broad")
			var along_x := kind.ends_with("_x")
			var width_x := pitch * (1.0 if not wide or along_x else 2.0)
			var width_z := pitch * (1.0 if not wide or not along_x else 2.0)
			var low: float = float(center[1]) * Geometry.HEIGHT_STEP
			var high: float = at.y + 0.082 + 0.12
			occupied += Vector3((width_x - pitch) * 0.5,
				(low + high) * 0.5 - occupied.y, (width_z - pitch) * 0.5)
			half = Vector3(width_x * 0.5, (high - low) * 0.5, width_z * 0.5)
		"anvil":
			var low: float = float(center[1]) * Geometry.HEIGHT_STEP
			var high := low + Geometry.PRESS_WORK_HEIGHT
			occupied.y = (low + high) * 0.5
			half = Vector3(Geometry.PITCH * 0.5, (high - low) * 0.5,
				Geometry.PITCH * 0.5)
		"broad_anvil":
			var low: float = float(center[1]) * Geometry.HEIGHT_STEP
			var high := low + Geometry.PRESS_WORK_HEIGHT
			occupied += Vector3(Geometry.PITCH * 0.5, (low + high) * 0.5 - occupied.y,
				Geometry.PITCH * 0.5)
			half = Vector3(Geometry.PITCH, (high - low) * 0.5, Geometry.PITCH)
		"ram_face":
			var low: float = float(center[1]) * Geometry.HEIGHT_STEP + Geometry.HEIGHT_STEP * 1.5
			var high := at.y + Geometry.HEIGHT_STEP * 0.5
			occupied.y = (low + high) * 0.5
			half.y = (high - low) * 0.5
		"flat_head":
			var low: float = float(center[1]) * Geometry.HEIGHT_STEP - Geometry.HEIGHT_STEP + Geometry.PRESS_WORK_HEIGHT
			var high := at.y + 0.125
			occupied.y = (low + high) * 0.5
			half = Vector3(Geometry.PITCH * 0.5, (high - low) * 0.5,
				Geometry.PITCH * 0.5)
		"broad_flat_head":
			var low: float = float(center[1]) * Geometry.HEIGHT_STEP - Geometry.HEIGHT_STEP + Geometry.PRESS_WORK_HEIGHT
			var high := at.y + Geometry.HEIGHT_STEP * 0.5
			occupied += Vector3(Geometry.PITCH * 0.5, (low + high) * 0.5 - occupied.y,
				Geometry.PITCH * 0.5)
			half = Vector3(Geometry.PITCH, (high - low) * 0.5, Geometry.PITCH)
		"broad_copper_slide":
			var low: float = float(center[1]) * Geometry.HEIGHT_STEP - 4.0 * Geometry.HEIGHT_STEP + Geometry.PRESS_WORK_HEIGHT
			var high := at.y + Geometry.ANCHOR_HEIGHT
			occupied += Vector3(Geometry.PITCH * 0.5, (low + high) * 0.5 - occupied.y,
				Geometry.PITCH * 0.5)
			half = Vector3(Geometry.PITCH, (high - low) * 0.5, Geometry.PITCH)
		"wooden_slide", "copper_slide":
			var low: float = float(center[1]) * Geometry.HEIGHT_STEP - 2.0 * Geometry.HEIGHT_STEP + Geometry.PRESS_WORK_HEIGHT
			var high := at.y + 0.08
			occupied.y = (low + high) * 0.5
			half = Vector3(Geometry.PITCH * 0.5, (high - low) * 0.5,
				Geometry.PITCH * 0.5)
		"sliding_guide":
			var low := at.y - Geometry.HEIGHT_STEP * 1.5
			var high := at.y + Geometry.HEIGHT_STEP - 0.08
			occupied.y = (low + high) * 0.5
			half.y = (high - low) * 0.5
		"tool_mount":
			occupied.y += 0.10
			half = Vector3(Geometry.HEIGHT_STEP - 0.205, 0.18, Geometry.HEIGHT_STEP - 0.205)
		"cutting_edge":
			occupied.y -= 0.015
			half = Vector3(0.21, 0.12, 0.18)
		"receiver_tray":
			occupied.y -= 0.0825
			half = Vector3(0.18, 0.15, 0.205)
		"wooden_shaft", "copper_shaft":
			half = Vector3(0.205, 0.12, 0.205)
		"wooden_cog", "copper_cog":
			half = Vector3(Geometry.HEIGHT_STEP - 0.205, 0.14, Geometry.HEIGHT_STEP - 0.205)
	return {"center": occupied, "half": half, "size": half * 2.0}

func _component_candidate_blocked(kind: String, center: Array, box: Dictionary) -> bool:
	if center.size() != 3:
		return true
	if kind == "broad_copper_slide":
		var supported := false
		for part: Dictionary in state.get("placed_components", {}).values():
			if part.get("component") == "broad_anvil" \
					and part.get("center") == [center[0], center[1] - 4, center[2]]:
				supported = true
				break
		if not supported:
			return true
	var result: Dictionary = Geometry.component_boxes(state)
	var occupied: Array = []
	if result.get("accepted", false):
		var paired_ids: Dictionary = {}
		for id: Variant in state.get("placed_components", {}):
			var part: Dictionary = state.placed_components[id]
			var part_center: Array = part.get("center", [])
			if part_center.size() != 3 or center.size() != 3:
				continue
			if kind == "broad_flat_head" and part.component == "broad_copper_slide" \
					and part_center == [center[0], center[1] + 3, center[2]]:
				paired_ids[id] = true
				continue
			if kind == "broad_copper_slide" and part.component == "broad_flat_head" \
					and center == [part_center[0], part_center[1] + 3, part_center[2]]:
				paired_ids[id] = true
				continue
			if ((kind == "anvil" and part.component == "receiver_tray") or \
					(kind == "receiver_tray" and part.component == "anvil")) \
					and part_center[1] == center[1] and (
						(absi(part_center[0] - center[0]) == 1 and part_center[2] == center[2]) or
						(part_center[0] == center[0] and absi(part_center[2] - center[2]) == 1)):
				paired_ids[id] = true
				continue
			if part_center[0] != center[0] or part_center[2] != center[2]:
				continue
			if (kind == "flat_head" and part.component in ["wooden_slide", "copper_slide"]
					and part_center[1] == center[1] + 1) or \
					(kind in ["wooden_slide", "copper_slide"] and part.component == "flat_head"
					and part_center[1] == center[1] - 1) or \
				(kind == "sliding_guide" and part.component == "ram_face"
					and part_center[1] == center[1] - 1) or \
				(kind == "ram_face" and part.component == "sliding_guide"
					and part_center[1] == center[1] + 1) or \
				(kind == "anvil" and part.component == "wooden_frame"
					and part_center[1] == center[1] - 1) or \
				(kind == "wooden_frame" and part.component == "anvil"
					and part_center[1] == center[1] + 1) or \
				(kind == "ram_face" and part.component == "wooden_frame"
					and part_center[1] == center[1] - 2) or \
				(kind == "wooden_frame" and part.component == "ram_face"
					and part_center[1] == center[1] + 2):
				paired_ids[id] = true
		for id: Variant in result.boxes:
			if not paired_ids.has(id):
				occupied.append(result.boxes[id])
	var mechanical: Dictionary = Geometry.mechanical_boxes(state)
	if mechanical.get("accepted", false):
		occupied.append_array(mechanical.get("boxes", {}).values())
	for foundation: Dictionary in state.get("foundations", {}).values():
		var cell: Variant = foundation.get("cell")
		if not cell is Array or cell.size() != 2 or typeof(foundation.get("level")) != TYPE_INT:
			continue
		var top := Vector3(cell[0] * Geometry.PITCH,
			foundation.level * Geometry.HEIGHT_STEP, cell[1] * Geometry.PITCH)
		occupied.append({"center": top - Vector3.UP * Geometry.FOUNDATION_DEPTH * 0.5,
			"size": Vector3(Geometry.PITCH, Geometry.FOUNDATION_DEPTH, Geometry.PITCH)})
	for entity: Dictionary in state.get("entities", {}).values():
		if entity.get("cell") is Array and entity.cell.size() == 2:
			occupied.append({"center": _entity_position(entity) + Vector3.UP * 0.8,
				"size": Vector3(Geometry.MACHINE_SIZE[0], Geometry.MACHINE_SIZE[1], Geometry.MACHINE_SIZE[2])})
	for actor: Dictionary in state.get("actors", {}).values():
		var position: Variant = actor.get("position")
		if Geometry.valid_position(position):
			occupied.append({"center": Vector3(position[0], position[1], position[2]),
				"size": Vector3(Geometry.CAPSULE_RADIUS * 2.0, Geometry.CAPSULE_HEIGHT,
					Geometry.CAPSULE_RADIUS * 2.0)})
	var source_contact := kind == "cutting_edge" and not _component_collector_face(kind, center).is_empty()
	if ProductionEnvironment.Surface != null:
		for solid: Dictionary in ProductionEnvironment.Surface.support_boxes():
			if solid.get("id", "") == "source_outcrop" and source_contact:
				continue
			var obstacle: AABB = Transform3D(solid.basis, solid.center) * AABB(-solid.size * 0.5, solid.size)
			occupied.append({"center": obstacle.get_center(), "size": obstacle.size})
	for other: Dictionary in occupied:
		var separation: Vector3 = (box.center - other.center).abs()
		var extent: Vector3 = (box.half + other.size * 0.5) - Vector3.ONE * 0.001
		if separation.x < extent.x and separation.y < extent.y and separation.z < extent.z:
			return true
	return false

func _refresh_component_preview() -> void:
	if component_preview == null:
		return
	component_preview.visible = false
	if press_snap_target != null:
		press_snap_target.visible = false
		press_snap_lift.visible = false
	if mode != "component" or not _native_transmission() or arrival_assembly_controls == null \
			or transmission_presenter == null or explanation_open or not _placement_ready() \
			or not _preview_pointer_clear():
		return
	var kind: String = arrival_assembly_controls.selected_name()
	var carried_kind := "anvil" if kind == "broad_anvil" else \
		"flat_head" if kind == "broad_flat_head" else \
		"copper_slide" if kind == "broad_copper_slide" else kind
	var needed := 4 if kind in ["broad_anvil", "broad_flat_head", "broad_copper_slide"] else 1
	if int(state.get("cargo", {}).get(client, {}).get("components", {}).get(carried_kind, 0)) < needed:
		return
	var pointed := _screen_entity(_pointed_screen_position()) if not component_nudge_active else ""
	var center := _component_place_center(_screen_cell(_pointed_screen_position()), pointed)
	if center.size() != 3:
		return
	if kind == "hand_crank":
		var input_id := _rotary_at_input_port(center)
		var input: Dictionary = state.get("placed_components", {}).get(input_id, {})
		component_preview_blocked = input_id.is_empty() or \
			not bool(input.get("crank_source_available", true))
		for item: Dictionary in state.get("crank_items", {}).values():
			if item.get("port", []) == center:
				component_preview_blocked = true
		component_preview_snap = "Rotary input" if not component_preview_blocked else "Point at a rotary input"
		if component_preview_pose_key != "hand_crank":
			for child in component_preview.get_children():
				child.free()
			transmission_presenter.preview_component(component_preview, kind, Vector3(0.25, 0.38, 0.22))
			component_preview_pose_key = "hand_crank"
			component_preview_kind = kind
			component_preview_material = StandardMaterial3D.new()
			component_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_style_component_preview(component_preview)
		component_preview.position = Vector3(float(center[0]) * Geometry.HEIGHT_STEP,
			float(center[1]) * Geometry.HEIGHT_STEP + Geometry.ANCHOR_HEIGHT,
			float(center[2]) * Geometry.HEIGHT_STEP)
		var input_cell: Array = input.get("center", [])
		var face := _crank_face_for_input(input_id, center)
		if face.size() != 3:
			face = [-1, 0, 0] if input_cell.size() == 3 and center[0] < input_cell[0] \
				else [1, 0, 0]
		var outward := Vector3(float(face[0]), 0.0, float(face[2]))
		component_preview.position += outward * 0.22
		component_preview.rotation.y = -atan2(outward.z, outward.x)
		component_preview_material.albedo_color = Color(0.94, 0.27, 0.21, 0.64) if component_preview_blocked \
			else Color(0.91, 0.73, 0.40, 0.56)
		component_preview.visible = true
		return
	component_preview.rotation.y = 0.0
	var box := _component_candidate_box(kind, center)
	component_preview_blocked = not _component_area_bounds_allowed(kind, center) or \
		_component_candidate_blocked(kind, center, box)
	component_preview_snap = ""
	if component_nudge_active:
		component_preview_snap = "Nudged point"
	elif state.get("placed_components", {}).has(pointed):
		var pointed_kind: String = str(state.placed_components[pointed].component)
		var hit := _screen_pick(_pointed_screen_position())
		var press_snap := _guided_press_part_snap(kind, pointed_kind,
			state.placed_components[pointed].center, hit.normal) if not hit.is_empty() else {}
		component_preview_snap = str(press_snap.label) if not press_snap.is_empty() else \
			("Above %s" % pointed_kind.replace("_", " ") if not hit.is_empty() and hit.normal.y > 0.5 \
			else "Beside %s" % pointed_kind.replace("_", " "))
		if press_snap_target != null and not press_snap.is_empty() \
				and (kind in ["flat_head", "broad_flat_head"] and pointed_kind in ["anvil", "broad_anvil"] \
				or kind in ["wooden_slide", "copper_slide"] and pointed_kind in ["anvil", "flat_head"]
				or kind == "broad_copper_slide" and pointed_kind == "broad_flat_head"):
			var target_box := _component_candidate_box(pointed_kind, state.placed_components[pointed].center)
			press_snap_target.position = target_box.center + Vector3.UP * (target_box.half.y + 0.015)
			press_snap_target.scale = Vector3(target_box.half.x / 0.77, 1.0, target_box.half.z / 0.77)
			press_snap_material.albedo_color = Color(0.94, 0.27, 0.21, 0.85) \
				if component_preview_blocked else Color(0.98, 0.73, 0.28, 0.9)
			press_snap_target.visible = true
			var camera_right: Vector3 = camera.global_transform.basis.x
			camera_right.y = 0.0
			var guide_bottom: float = target_box.center.y - target_box.half.y + 0.02 \
				if pointed_kind == "flat_head" else target_box.center.y + target_box.half.y + 0.025
			var guide_top: float = box.center.y + box.half.y - 0.025
			press_snap_lift.scale.y = maxf(0.35, (guide_top - guide_bottom) / 0.82)
			press_snap_lift_tip.scale.y = 0.5 / press_snap_lift.scale.y
			press_snap_lift_tip.position.y = 0.455 - 0.0375 / press_snap_lift.scale.y
			press_snap_lift.position = Vector3(target_box.center.x,
				guide_bottom + press_snap_lift.scale.y * 0.365, target_box.center.z) \
				+ camera_right.normalized() * (0.28 if pointed_kind == "flat_head" else 0.22)
			press_snap_lift_material.albedo_color = press_snap_material.albedo_color
			press_snap_lift.visible = true
	else:
		component_preview_snap = "Floor grid"
	var collector_face := _component_collector_face(kind, center)
	var collector_angle := 0.0
	var collector_support_drop := 0.0
	var visual_center: Vector3 = box.center
	if not collector_face.is_empty():
		var toward: Array = collector_face.toward_ore
		collector_angle = atan2(float(toward[2]), -float(toward[0]))
		var floor_y: float = collector_face.center[1] * Geometry.HEIGHT_STEP
		visual_center.y = center[1] * Geometry.HEIGHT_STEP + Geometry.ANCHOR_HEIGHT \
			+ (0.10 if kind == "tool_mount" else -0.015)
		collector_support_drop = visual_center.y - floor_y
	var preview_key := "%s:%s:%s" % [kind, collector_angle, collector_support_drop]
	if preview_key != component_preview_pose_key:
		for child in component_preview.get_children():
			child.free()
		transmission_presenter.preview_component(component_preview, kind, box.size,
			collector_angle, collector_support_drop)
		component_preview_kind = kind
		component_preview_pose_key = preview_key
		component_preview_material = StandardMaterial3D.new()
		component_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		component_preview_material.roughness = 0.72
		_style_component_preview(component_preview)
	component_preview.position = visual_center
	component_preview_material.albedo_color = Color(0.94, 0.27, 0.21, 0.64) if component_preview_blocked \
		else Color(0.91, 0.73, 0.40, 0.56)
	component_preview.visible = true

func _style_component_preview(node: Node, material: StandardMaterial3D = null) -> void:
	if node is MeshInstance3D:
		node.material_override = material if material != null else component_preview_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_style_component_preview(child, material)

func _component_placement_hint() -> String:
	if component_preview == null or not component_preview.visible:
		return "Point at a floor or built part"
	if arrival_assembly_controls != null and arrival_assembly_controls.selected_name() == "hand_crank":
		var crank_center := _component_place_center(_screen_cell(_pointed_screen_position()),
			_screen_entity(_pointed_screen_position()))
		var input_id := _rotary_at_input_port(crank_center)
		if not input_id.is_empty() and not bool(state.get("placed_components", {}).get(
				input_id, {}).get("crank_source_available", true)):
			return "A waterwheel already powers this shaft network"
		return "Point at a slide input shaft end · click to place the carried crank" \
			if not component_preview_blocked else "Point at a clear slide input shaft end"
	var center := _component_place_center(_screen_cell(_pointed_screen_position()),
		_screen_entity(_pointed_screen_position()))
	var location := "%s · X %d  Y %d  Z %d" % [component_preview_snap, center[0], center[1], center[2]]
	var action := "Blocked here · move the ghost" if component_preview_blocked else "Click to place"
	var kind: String = arrival_assembly_controls.selected_name()
	var stack_hint := "Aim at a clear 2×2 floor area; uses four anvils" if kind == "broad_anvil" else \
		"Aim at the 2×2 workbed; uses four flat heads" if kind == "broad_flat_head" else \
		"Aim at the 2×2 head; uses four copper slides" if kind == "broad_copper_slide" else \
		"Aim at a floor or built surface" if kind == "anvil" else \
		"Aim at the anvil to place the head above" if kind == "flat_head" else \
		"Aim at the anvil or flat head to place the slide above" if kind in ["wooden_slide", "copper_slide"] else \
		"Aim at the anvil top" if kind == "ram_face" else \
		"Aim at the anvil or ram top" if kind == "sliding_guide" else \
		"Press drive: aim at anvil side or guide side" if kind in ["wooden_shaft", "copper_shaft"] else \
		"Press drive: aim at anvil side or shaft end" if kind in ["wooden_cog", "copper_cog"] else \
		"Point at a part face to snap"
	return "%s\n%s · %s\nAlt + arrows / PgUp / PgDn nudges" % [location, action, stack_hint]

func _screen_pick(screen: Vector2) -> Dictionary:
	if camera == null or not camera.is_inside_tree():
		return {}
	var origin := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen) * 80)
	query.collision_mask = Geometry.PICK_LAYER | Geometry.MACHINE_LAYER | TRANSMISSION_TERRAIN_PICK_LAYER
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider.has_meta("transmission_terrain"):
		return {}
	return hit

func _entity_at_cell(cell: Vector2i) -> String:
	for entity_id in state.get("entities", {}):
		if state.entities[entity_id].cell == [cell.x, cell.y]:
			return entity_id
	return ""

func _cell_position(cell: Array) -> Vector3:
	return Vector3(cell[0] * PITCH, 0, cell[1] * PITCH)

func _entity_position(entity: Dictionary) -> Vector3:
	return _cell_position(entity.cell) + Vector3.UP * float(entity.get("level", 0)) * Geometry.HEIGHT_STEP

func _build_cell_allowed(cell: Vector2i) -> bool:
	if mode != "foundation" and _native_transmission() and ProductionEnvironment.Surface != null:
		var half: float = ProductionEnvironment.Surface.HALF - PITCH / 2.0
		return absf(cell.x * PITCH) <= half and absf(cell.y * PITCH) <= half
	return absi(cell.x) <= 250000 and absi(cell.y) <= 250000

func _construction_level(cell: Vector2i) -> int:
	if mode == "foundation":
		return foundation_level
	if mode == "wheel":
		return wheel_level
	var top := -1000001
	for surface: Dictionary in state.get("foundations", {}).values():
		if surface.cell == [cell.x, cell.y]:
			top = maxi(top, int(surface.level))
	return top if top > -1000001 else 0

func _adjust_foundation_level(delta: int) -> void:
	if mode not in ["foundation", "wheel"] or not _native_transmission() or explanation_open:
		return
	if mode == "wheel":
		wheel_level = clampi(wheel_level + delta * Geometry.HEIGHT_DENOMINATOR, -1000000, 1000000)
	else:
		var step := 1 if foundation_steps else Geometry.FOUNDATION_HEIGHT_UNITS
		foundation_level = clampi(foundation_level + delta * step, -1000000, 1000000)
	foundation_area_started = false
	foundation_level_label.text = _construction_height_text()
	_message(_construction_height_text() + ". Access steps are for walking; machines need a factory floor.")

func _set_foundation_steps(enabled: bool) -> void:
	foundation_steps = enabled
	if not enabled:
		foundation_level = roundi(float(foundation_level) / Geometry.HEIGHT_DENOMINATOR) * Geometry.HEIGHT_DENOMINATOR
	foundation_area_started = false
	foundation_level_label.text = _construction_height_text()
	_message(_construction_height_text() + ". Existing foundations stay at their built heights.")

func _construction_height_text() -> String:
	var level := wheel_level if mode == "wheel" else foundation_level
	var caption := "Drive height" if mode == "wheel" else "Factory floor" if level % Geometry.HEIGHT_DENOMINATOR == 0 else "Access step"
	return "%s · %.2f m" % [caption, level * Geometry.HEIGHT_STEP]

func _machine_floor_aligned(cell: Vector2i) -> bool:
	# Only suppress a known impossible height. Host still decides support,
	# terrain, occupancy and reach; an amber preview never promises admission.
	return not _native_transmission() or mode not in ["collector", "belt", "processor", "wheel"] \
		or _construction_level(cell) % Geometry.HEIGHT_DENOMINATOR == 0

func _adjust_wheel_size(delta: int) -> void:
	if mode != "wheel" or not _native_transmission() or explanation_open:
		return
	wheel_tiles = clampi(wheel_tiles + delta, 3, 4096)
	wheel_size_label.text = "Wheel diameter: %d squares" % wheel_tiles

func _assemble_foundation(parent: Node3D, neighbor_mask: int = 0) -> void:
	# Only confirmed player-built surfaces or an explicit placement preview
	# call this; the unbuilt site receives no manufactured structures.
	if not ProductionFoundationArt.mount(parent, neighbor_mask):
		push_error("The foundation needs its complete concrete and steel art kit.")
		if is_inside_tree():
			get_tree().quit(1)

func _update_camera() -> void:
	var back := Vector3(sin(orbit_yaw) * cos(orbit_pitch), sin(orbit_pitch), cos(orbit_yaw) * cos(orbit_pitch))
	var eye_offset := FIRST_PERSON_EYE_OFFSET * (1.0 - clampf(distance / FIRST_PERSON_BLEND_DISTANCE, 0.0, 1.0))
	camera.position = focus + Vector3.UP * eye_offset + back * distance
	# At zero distance look along the same orbit ray instead of looking at the
	# camera's own position. The local mesh remains real but cannot fill the view.
	camera.look_at(camera.position - back)
	if character_presenter != null and character_presenter.views.has(client):
		var local_view: Node3D = character_presenter.views[client]
		var local_actor: Dictionary = state.get("actors", {}).get(client, {})
		local_view.visible = distance > 1.0 and local_actor.get("ready", false) \
			and Geometry.valid_position(local_actor.get("position"))
	if status_footer != null:
		var footer_anchor := 0.0 if _footer_above_view() else 1.0
		if not is_equal_approx(status_footer.anchor_top, footer_anchor):
			_queue_footer_fit()
	if arrival_reveal_active:
		_update_arrival_reveal_camera()

func _build_world() -> void:
	if ProductionEnvironment.Surface == null:
		push_error("Opening requires authored site geometry")
		if is_inside_tree():
			get_tree().quit(1)
		return
	ProductionEnvironment.build(self)
	var surface = ProductionEnvironment.Surface
	var natural_ground: ShaderMaterial = ProductionEnvironment.ground_material()
	if natural_ground == null:
		if is_inside_tree():
			get_tree().quit(1)
		return
	var natural_stone: StandardMaterial3D = ProductionEnvironment.stone_material()
	set_meta("foundation_surface", ProductionEnvironment.ground_source_status)
	var groups := {"": self}
	var headwall := Node3D.new()
	headwall.name = "NorthSeamOutcrop"
	headwall.position = surface.group_origin("NorthSeamOutcrop")
	add_child(headwall)
	groups.NorthSeamOutcrop = headwall
	for spec in surface.foundation_boxes():
		var part := _machine_box(groups[spec.group], spec.label,
			spec.center - surface.group_origin(spec.group), spec.size, spec.tint, spec.metallic, spec.roughness)
		part.set_meta("site_solid_id", spec.id)
		if spec.label in ["EastBedrockShelf", "WestBankBedrockShelf"] and natural_ground != null:
			part.material_override = natural_ground
		elif spec.label in ["EastBedrockRim", "WestBedrockRim", "EastShelfOutcrop", "WestShelfOutcrop", "StreamBankLedge"] and natural_stone != null:
			part.material_override = natural_stone
	for spec in surface.pad_panels():
		var tint := Color("74766b").darkened(float(posmod(spec.cell.x * 17 + spec.cell.y * 31, 5)) * 0.018)
		var panel := _machine_box(self, "BedrockTerracePanel", spec.center, spec.size, tint, 0.0, 0.94)
		panel.set_meta("surface_role", "foundation")
		panel.set_meta("site_solid_id", spec.id)
		if natural_ground != null:
			panel.material_override = natural_ground
	_install_transmission_terrain_picker()
	machine_root = Node3D.new()
	add_child(machine_root)
	component_preview = Node3D.new()
	component_preview.name = "ComponentPreview"
	component_preview.visible = false
	add_child(component_preview)
	press_snap_target = _selection_outline()
	press_snap_target.name = "PressSnapTarget"
	press_snap_material = press_snap_target.material_override.duplicate() as StandardMaterial3D
	press_snap_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	press_snap_target.material_override = press_snap_material
	press_snap_target.visible = false
	press_snap_lift = Node3D.new()
	press_snap_lift.name = "PressSnapLift"
	press_snap_lift_material = StandardMaterial3D.new()
	press_snap_lift_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	press_snap_lift_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for dash_y in [-0.30, -0.08, 0.14]:
		var dash := MeshInstance3D.new()
		var stem := CylinderMesh.new()
		stem.top_radius = 0.009
		stem.bottom_radius = 0.009
		stem.height = 0.13
		dash.mesh = stem
		dash.position.y = dash_y
		dash.material_override = press_snap_lift_material
		dash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		press_snap_lift.add_child(dash)
	press_snap_lift_tip = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.045
	cone.height = 0.15
	press_snap_lift_tip.mesh = cone
	press_snap_lift_tip.position.y = 0.38
	press_snap_lift_tip.material_override = press_snap_lift_material
	press_snap_lift_tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	press_snap_lift.add_child(press_snap_lift_tip)
	press_snap_lift.visible = false
	add_child(press_snap_lift)
	item_root = Node3D.new()
	add_child(item_root)
	hover = _box(self, Vector3.ZERO, Vector3(1.5, 0.035, 1.5), Color(0.85, 0.75, 0.45, 0.45))
	hover.visible = false
	selection_ring = _selection_outline()
	selection_ring.visible = false
	camera = Camera3D.new()
	# Keep the full guided press in view while aiming from reachable actor distance.
	camera.fov = 65
	camera.near = 0.1
	camera.far = 100
	add_child(camera)
	camera.make_current()
	_update_camera()

func _pod_panel(parent: Node3D, part_name: String, profile: PackedVector2Array,
		depth: float, at: Vector3, finish: Material, bevel: float = 0.012) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = ProductionVisuals.prism_mesh(profile, depth, bevel)
	part.position = at
	part.material_override = finish
	parent.add_child(part)
	return part

func _build_landing_pod_visual(pod: Dictionary, hub: Dictionary) -> void:
	landing_pod_visual = Node3D.new()
	landing_pod_visual.name = "DeployedLandingPod"
	landing_pod_visual.set_meta("authority_entity", pod.id)
	add_child(landing_pod_visual)
	var shell := Node3D.new()
	shell.name = "OpenedPodShell"
	landing_pod_visual.add_child(shell)
	var graphite := Color("293a3c")
	var amber := Color("be8d43")
	var dark := Color("17282c")
	var hull_finish := ProductionCoating.material(Color("74766d"))
	var service_finish := ProductionCoating.material(Color("394347"))
	var worked_finish := ProductionTransmissionFinish.material("worked", Color("91938b"), 0.75, 0.48)
	# One pressure canopy closes over the pallet in flight, then hinges back.
	# The folded cover parks behind the pallet, clearing the front and east aisle.
	_pod_panel(shell, "LowerHull", PackedVector2Array([
		Vector2(-0.56, 0.12), Vector2(0.56, 0.12), Vector2(0.67, 0.17),
		Vector2(0.74, 0.26), Vector2(0.72, 0.34), Vector2(0.64, 0.43),
		Vector2(-0.64, 0.43), Vector2(-0.72, 0.34), Vector2(-0.74, 0.26),
		Vector2(-0.67, 0.17)]),
		1.76, Vector3(0, 0, 0.02), ProductionCoating.material(graphite))
	var pallet := _pod_panel(shell, "InteriorPallet", PackedVector2Array([
		Vector2(-0.535, -0.585), Vector2(-0.415, -0.705),
		Vector2(0.415, -0.705), Vector2(0.535, -0.585),
		Vector2(0.535, 0.585), Vector2(0.415, 0.705),
		Vector2(-0.415, 0.705), Vector2(-0.535, 0.585)]),
		0.055, Vector3(0, 0.43, -0.03), service_finish, 0.006)
	pallet.rotation.x = PI / 2.0
	_pod_panel(shell, "RearBulkhead", PackedVector2Array([
		Vector2(-0.56, 0.37), Vector2(0.56, 0.37), Vector2(0.56, 0.81),
		Vector2(0.42, 0.95), Vector2(-0.42, 0.95), Vector2(-0.56, 0.81)]),
		0.12, Vector3(0, 0, 0.79), service_finish)
	var canopy := Node3D.new()
	canopy.name = "CanopyPivot"
	canopy.position = Vector3(0, 0.72, 0.80)
	shell.add_child(canopy)
	var inner_arch := PackedVector2Array([
		Vector2(0.56, 0.38), Vector2(0.56, 0.84), Vector2(0.54, 1.00),
		Vector2(0.48, 1.12), Vector2(0.37, 1.22), Vector2(0.20, 1.28),
		Vector2(-0.20, 1.28), Vector2(-0.37, 1.22), Vector2(-0.48, 1.12),
		Vector2(-0.54, 1.00), Vector2(-0.56, 0.84), Vector2(-0.56, 0.38)])
	var canopy_profile := PackedVector2Array([
		Vector2(-0.68, 0.38), Vector2(-0.68, 0.48), Vector2(-0.668, 0.53),
		Vector2(-0.668, 0.88), Vector2(-0.65, 1.05), Vector2(-0.58, 1.20),
		Vector2(-0.48, 1.32), Vector2(-0.34, 1.39), Vector2(-0.16, 1.42),
		Vector2(0.16, 1.42), Vector2(0.34, 1.39), Vector2(0.48, 1.32),
		Vector2(0.58, 1.20), Vector2(0.65, 1.05), Vector2(0.668, 0.88),
		Vector2(0.668, 0.53), Vector2(0.68, 0.48), Vector2(0.68, 0.38)])
	canopy_profile.append_array(inner_arch)
	_pod_panel(canopy, "PressureCanopy", canopy_profile,
		1.70, Vector3(0, -0.72, -0.85), hull_finish, 0.008)
	var liner_profile := inner_arch.duplicate()
	var liner_return := inner_arch.duplicate()
	liner_return.reverse()
	for index in range(liner_return.size()):
		liner_return[index].x *= 0.965
		liner_return[index].y = maxf(0.38, liner_return[index].y - 0.014)
	liner_profile.append_array(liner_return)
	_pod_panel(canopy, "CanopyLiner", liner_profile,
		1.49, Vector3(0, -0.72, -0.85), service_finish, 0.002)
	_pod_panel(canopy, "ForwardHatch", inner_arch,
		0.075, Vector3(0, -0.72, -1.72), ProductionCoating.material(graphite))
	_pod_panel(canopy, "SmokedVisor", PackedVector2Array([
		Vector2(-0.36, 0.78), Vector2(0.36, 0.78), Vector2(0.33, 1.00),
		Vector2(0.22, 1.12), Vector2(0.08, 1.16), Vector2(-0.08, 1.16),
		Vector2(-0.22, 1.12), Vector2(-0.33, 1.00)]),
		0.008, Vector3(0, -0.72, -1.754), ProductionVisuals.material(Color("36585e"), 0.05, 0.22), 0.002)
	_pod_panel(canopy, "HatchLatch", PackedVector2Array([
		Vector2(-0.115, -0.02), Vector2(-0.10, -0.0325),
		Vector2(0.10, -0.0325), Vector2(0.115, -0.02),
		Vector2(0.115, 0.02), Vector2(0.10, 0.0325),
		Vector2(-0.10, 0.0325), Vector2(-0.115, 0.02)]),
		0.018, Vector3(0, -0.14, -1.75), ProductionCoating.material(amber), 0.003)
	for side in [-1.0, 1.0]:
		var suffix := "Port" if side < 0.0 else "Starboard"
		var panel := _pod_panel(canopy, suffix + "ServicePanel", PackedVector2Array([
			Vector2(-0.65, 0.56), Vector2(-0.60, 0.52), Vector2(0.60, 0.52),
			Vector2(0.65, 0.56), Vector2(0.65, 0.82), Vector2(0.60, 0.86),
			Vector2(-0.60, 0.86), Vector2(-0.65, 0.82)]),
			0.006, Vector3(side * 0.672, -0.72, -0.85), service_finish, 0.002)
		panel.rotation.y = side * PI / 2.0
		_machine_box(canopy, suffix + "CanopyStripe", Vector3(side * 0.11, 0.709, -0.85),
			Vector3(0.055, 0.018, 1.51), amber, 0.18, 0.69)
	for side in [-1.0, 1.0]:
		var suffix := "Port" if side < 0.0 else "Starboard"
		var hinge := _machine_cylinder(shell, suffix + "CanopyHinge", Vector3(side * 0.53, 0.72, 0.80),
			0.09, 0.21, graphite, Vector3(0, 0, PI / 2.0))
		hinge.material_override = worked_finish
		_machine_cylinder(shell, suffix + "CanopyStrut", Vector3.ZERO, 0.026, 1.0, Color("8d9c99"))
		for z in [-0.72, 0.72]:
			var end := "Front" if z < 0 else "Rear"
			var foot := _pod_panel(shell, suffix + "LandingFoot" + end, PackedVector2Array([
				Vector2(-0.14, -0.10), Vector2(-0.095, -0.145),
				Vector2(0.095, -0.145), Vector2(0.14, -0.10),
				Vector2(0.14, 0.10), Vector2(0.095, 0.145),
				Vector2(-0.095, 0.145), Vector2(-0.14, 0.10)]),
				0.14, Vector3(side * 0.65, 0.07, z), ProductionCoating.material(graphite), 0.008)
			foot.rotation.x = PI / 2.0
			_machine_box(shell, suffix + "PalletSkid" + end, Vector3(side * 0.58, 0.15, z),
				Vector3(0.09, 0.18, 0.13), graphite, 0.45, 0.68)
	landing_hub_visual = Node3D.new()
	landing_hub_visual.name = "PodFabricationHub"
	landing_hub_visual.set_meta("authority_entity", hub.id)
	add_child(landing_hub_visual)
	landing_hub_pick = StaticBody3D.new()
	landing_hub_pick.name = "WorkshopPickBody"
	landing_hub_pick.set_meta("component_entity", hub.id)
	landing_hub_pick.collision_layer = Geometry.PICK_LAYER
	landing_hub_pick.collision_mask = 0
	landing_hub_pick.position.y = 0.68
	var pick_shape := CollisionShape3D.new()
	pick_shape.name = "PickShape"
	var pick_box := BoxShape3D.new()
	pick_box.size = Vector3(1.16, 1.25, 0.70)
	pick_shape.shape = pick_box
	landing_hub_pick.add_child(pick_shape)
	landing_hub_visual.add_child(landing_hub_pick)
	var workspace := Node3D.new()
	workspace.name = "FoldoutBench"
	landing_hub_visual.add_child(workspace)
	var frame_finish := ProductionCoating.material(graphite)
	var work_finish := ProductionTransmissionFinish.material("worked", Color("50504b"), 0.55, 0.57)
	var steel_finish := ProductionTransmissionFinish.material("worked", Color("979a95"), 0.85, 0.42)
	var tool_finish := ProductionCoating.material(Color("99713c"))
	for x in [-0.40, 0.40]:
		var side := "West" if x < 0 else "East"
		for z in [-0.27, 0.27]:
			_pod_panel(workspace, "BenchLeg%s%s" % [side, "Front" if z < 0 else "Rear"], PackedVector2Array([
				Vector2(-0.0425, 0), Vector2(0.0425, 0),
				Vector2(0.0425, 0.68), Vector2(-0.0425, 0.68)]),
				0.085, Vector3(x, 0, z), frame_finish, 0.004)
		var brace := _pod_panel(workspace, "BenchLockBrace" + side, PackedVector2Array([
			Vector2(-0.27, 0.60), Vector2(0.27, 0.60),
			Vector2(0.27, 0.53), Vector2(-0.27, 0.32)]),
			0.035, Vector3(x, 0, 0), frame_finish, 0.004)
		brace.rotation.y = PI / 2.0
	for z in [-0.27, 0.27]:
		var rail := _machine_box(workspace, "BenchFrontApron" if z < 0 else "BenchRearApron", Vector3(0, 0.645, z),
			Vector3(0.88, 0.09, 0.06), graphite)
		rail.material_override = frame_finish
	var worktop := _pod_panel(workspace, "BenchWorktop", PackedVector2Array([
		Vector2(-0.58, -0.30), Vector2(-0.53, -0.35), Vector2(0.53, -0.35),
		Vector2(0.58, -0.30), Vector2(0.58, 0.30), Vector2(0.53, 0.35),
		Vector2(-0.53, 0.35), Vector2(-0.58, 0.30)]),
		0.115, Vector3(0, 0.74, 0), work_finish, 0.008)
	worktop.rotation.x = PI / 2.0
	var bed := _machine_box(workspace, "BenchSteelInsert", Vector3(-0.16, 0.805, -0.06),
		Vector3(0.52, 0.02, 0.38), Color("596e6d"))
	bed.material_override = steel_finish
	for spec in [[-0.35, 1.0, "Fixed"], [0.03, -1.0, "Sliding"]]:
		var x: float = spec[0]
		var jaw_name: String = spec[2]
		_pod_panel(workspace, "Vise" + jaw_name + "Jaw", PackedVector2Array([
			Vector2(-0.0375, -0.065), Vector2(0.0375, -0.065),
			Vector2(0.033, 0.035), Vector2(0.018, 0.065),
			Vector2(-0.018, 0.065), Vector2(-0.0375, 0.035)]),
			0.27, Vector3(x, 0.88, -0.06), frame_finish, 0.004)
		var face := _machine_box(workspace, "Vise" + jaw_name + "Face", Vector3(x + spec[1] * 0.032, 0.90, -0.06),
			Vector3(0.009, 0.075, 0.25), Color("78867e"))
		face.material_override = steel_finish
	var lead_screw := _machine_cylinder(workspace, "ViseLeadScrew", Vector3(-0.10, 0.847, -0.06),
		0.014, 0.50, Color("979a95"), Vector3(0, 0, PI / 2.0))
	lead_screw.material_override = steel_finish
	var handle_boss := _machine_cylinder(workspace, "ViseHandleBoss", Vector3(0.16, 0.847, -0.06),
		0.028, 0.04, Color("979a95"), Vector3(0, 0, PI / 2.0))
	handle_boss.material_override = steel_finish
	var sliding_handle := _machine_cylinder(workspace, "ViseSlidingHandle", Vector3(0.16, 0.847, -0.06),
		0.008, 0.14, Color("979a95"))
	sliding_handle.material_override = steel_finish
	_pod_panel(workspace, "ToolPost", PackedVector2Array([
		Vector2(-0.07, -0.22), Vector2(0.07, -0.22), Vector2(0.07, -0.16),
		Vector2(0.045, -0.12), Vector2(0.045, 0.18), Vector2(0.03, 0.22),
		Vector2(-0.03, 0.22), Vector2(-0.045, 0.18),
		Vector2(-0.045, -0.12), Vector2(-0.07, -0.16)]),
		0.14, Vector3(0.35, 1.01, -0.19), frame_finish, 0.005)
	_pod_panel(workspace, "ToolArm", PackedVector2Array([
		Vector2(-0.285, -0.018), Vector2(-0.265, -0.0325),
		Vector2(0.285, -0.0325), Vector2(0.285, 0.0325),
		Vector2(-0.265, 0.0325), Vector2(-0.285, 0.018)]),
		0.065, Vector3(0.065, 1.23, -0.19), frame_finish, 0.004)
	_pod_panel(workspace, "CuttingHead", PackedVector2Array([
		Vector2(-0.06, 0.085), Vector2(0.06, 0.085), Vector2(0.055, -0.02),
		Vector2(0.025, -0.07), Vector2(0.02, -0.085), Vector2(-0.02, -0.085),
		Vector2(-0.025, -0.07), Vector2(-0.055, -0.02)]),
		0.13, Vector3(-0.16, 1.16, -0.19), tool_finish, 0.004)
	var spindle := _machine_cylinder(workspace, "CuttingSpindle", Vector3(-0.16, 1.06, -0.19),
		0.012, 0.04, Color("979a95"))
	spindle.material_override = steel_finish
	var mounting_points := [Vector3(-0.39, 0.82, 0.09), Vector3(0.07, 0.82, 0.09),
		Vector3(0.30, 0.805, -0.23), Vector3(0.40, 0.805, -0.23)]
	for index in range(mounting_points.size()):
		var bolt := MeshInstance3D.new()
		bolt.name = "BenchFastener%d" % index
		bolt.mesh = ProductionVisuals.fastener_head_mesh()
		bolt.material_override = steel_finish
		bolt.position = mounting_points[index]
		bolt.scale = Vector3.ONE * 0.5
		workspace.add_child(bolt)
	_pose_pod_canopy(1.0)

func _pose_pod_canopy(amount: float) -> void:
	var shell: Node3D = landing_pod_visual.get_node("OpenedPodShell")
	var canopy: Node3D = shell.get_node("CanopyPivot")
	canopy.rotation.x = PI * amount
	for side in [-1.0, 1.0]:
		var start := Vector3(side * 0.62, 0.28, 0.10)
		var end: Vector3 = canopy.transform * Vector3(side * 0.62, 0.25, -0.90)
		var strut: MeshInstance3D = shell.get_node(("Port" if side < 0.0 else "Starboard") + "CanopyStrut")
		strut.position = (start + end) * 0.5
		strut.basis = Basis.looking_at((end - start).normalized(), Vector3.RIGHT) * Basis(Vector3.RIGHT, PI / 2.0)
		strut.scale = Vector3(1.0, start.distance_to(end), 1.0)

func _collect_static_descendant_parts(node: Node3D, pose: Transform3D, finishes: Dictionary) -> void:
	for child in node.get_children():
		if not child is Node3D:
			continue
		var child_3d := child as Node3D
		var child_pose: Transform3D = pose * child_3d.transform
		if child_3d is MeshInstance3D:
			var source := child_3d as MeshInstance3D
			if source.mesh != null:
				for surface in source.mesh.get_surface_count():
					var finish: Material = source.material_override
					if finish == null:
						finish = source.get_surface_override_material(surface)
					if finish == null:
						finish = source.mesh.surface_get_material(surface)
					var finish_id := finish.get_instance_id() if finish != null else 0
					if not finishes.has(finish_id):
						var st := SurfaceTool.new()
						st.begin(Mesh.PRIMITIVE_TRIANGLES)
						st.set_material(finish)
						finishes[finish_id] = st
					(finishes[finish_id] as SurfaceTool).append_from(source.mesh, surface, child_pose)
		_collect_static_descendant_parts(child_3d, child_pose, finishes)

func _set_descendant_meshes_visible(node: Node3D, show_meshes: bool) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visible = show_meshes
		if child is Node3D:
			_set_descendant_meshes_visible(child as Node3D, show_meshes)

func _sync_landing_pod_visual() -> void:
	if not state.has("landing_pod") or not state.has("fabrication_hub"):
		if landing_pod_visual != null:
			landing_pod_visual.free()
			landing_hub_visual.free()
			landing_pod_visual = null
			landing_hub_visual = null
			landing_hub_pick = null
		if landing_pod_batch_visual != null:
			landing_pod_batch_visual.free()
			landing_pod_batch_visual = null
		if landing_hub_batch_visual != null:
			landing_hub_batch_visual.free()
			landing_hub_batch_visual = null
		return
	var pod: Dictionary = state.landing_pod
	var hub: Dictionary = state.fabrication_hub
	if not pod.get("deployed", false):
		return
	if landing_pod_visual == null:
		_build_landing_pod_visual(pod, hub)
	var pod_center: Array = pod.center
	var pod_floor := Vector3(float(pod_center[0]) * PITCH,
		float(pod_center[1]) * Geometry.HEIGHT_STEP, float(pod_center[2]) * PITCH)
	if not arrival_reveal_active:
		landing_pod_visual.position = pod_floor
	var installed: bool = hub.get("installed", false)
	landing_hub_visual.visible = installed
	landing_hub_pick.collision_layer = Geometry.PICK_LAYER if installed else 0
	if installed and hub.has("position"):
		var position: Array = hub.position
		# Host positions use the shared spindle anchor; the bench art sits on its floor.
		landing_hub_visual.position = Vector3(float(position[0]), float(position[1]), float(position[2])) \
			- Vector3.UP * Geometry.ANCHOR_HEIGHT
	var batch_pod: bool = not arrival_reveal_active and state.get("placed_components", {}).size() >= 12
	if batch_pod:
		if landing_pod_batch_visual == null:
			var pod_finishes := {}
			_collect_static_descendant_parts(landing_pod_visual, Transform3D.IDENTITY, pod_finishes)
			var pod_mesh: ArrayMesh
			for st: SurfaceTool in pod_finishes.values():
				pod_mesh = st.commit(pod_mesh)
			landing_pod_batch_visual = MeshInstance3D.new()
			landing_pod_batch_visual.name = "DeployedLandingPodBatch"
			landing_pod_batch_visual.mesh = pod_mesh
			add_child(landing_pod_batch_visual)
		if landing_hub_batch_visual == null:
			var hub_finishes := {}
			_collect_static_descendant_parts(landing_hub_visual, Transform3D.IDENTITY, hub_finishes)
			var hub_mesh: ArrayMesh
			for st: SurfaceTool in hub_finishes.values():
				hub_mesh = st.commit(hub_mesh)
			landing_hub_batch_visual = MeshInstance3D.new()
			landing_hub_batch_visual.name = "PodFabricationHubBatch"
			landing_hub_batch_visual.mesh = hub_mesh
			add_child(landing_hub_batch_visual)
		_set_descendant_meshes_visible(landing_pod_visual, false)
		_set_descendant_meshes_visible(landing_hub_visual, false)
		landing_pod_batch_visual.transform = landing_pod_visual.transform
		landing_pod_batch_visual.visible = landing_pod_visual.visible
		landing_hub_batch_visual.transform = landing_hub_visual.transform
		landing_hub_batch_visual.visible = landing_hub_visual.visible
	else:
		if landing_pod_batch_visual != null:
			landing_pod_batch_visual.visible = false
		if landing_hub_batch_visual != null:
			landing_hub_batch_visual.visible = false
		_set_descendant_meshes_visible(landing_pod_visual, true)
		_set_descendant_meshes_visible(landing_hub_visual, true)

func _maybe_start_arrival_reveal() -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while is_inside_tree() and get_node_or_null("MachinePreviewWarmup") != null \
			and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not is_inside_tree() or get_node_or_null("MachinePreviewWarmup") != null \
			or landing_pod_visual == null or landing_hub_visual == null:
		return
	arrival_reveal_pod_anchor = landing_pod_visual.position
	arrival_reveal_elapsed = 0.0
	_release_character_controls()
	arrival_reveal_active = true
	_sync_landing_pod_visual()
	if character_presenter != null:
		character_presenter.visible = false
	if arrival_gameplay_canvas != null:
		arrival_gameplay_canvas.visible = false
	if arrival_reveal_canvas != null:
		arrival_reveal_canvas.visible = true
	if arrival_reveal_audio == null:
		arrival_reveal_audio = ArrivalRevealAudio.new()
		arrival_reveal_audio.name = "ArrivalRevealAudio"
		add_child(arrival_reveal_audio)
	arrival_reveal_audio.begin()
	_refresh_ui()
	_advance_arrival_reveal(0.0)

func _arrival_fold_amount() -> float:
	var phase := clampf((arrival_reveal_elapsed - 1.45) / 1.20, 0.0, 1.0)
	return phase * phase * (3.0 - 2.0 * phase)

func _pose_arrival_reveal() -> void:
	var descent := clampf(arrival_reveal_elapsed / 1.45, 0.0, 1.0)
	descent = descent * descent * (3.0 - 2.0 * descent)
	var fold := _arrival_fold_amount()
	landing_pod_visual.position = arrival_reveal_pod_anchor + Vector3.UP * (8.0 * (1.0 - descent))
	landing_pod_visual.rotation.y = 0.18 * (1.0 - descent)
	_pose_pod_canopy(smoothstep(0.0, 0.60, fold))
	var bench_fold := smoothstep(0.35, 1.0, fold)
	var workspace: Node3D = landing_hub_visual.get_node("FoldoutBench")
	workspace.position = (arrival_reveal_pod_anchor - landing_hub_visual.position) * (1.0 - bench_fold) \
		+ Vector3.UP * (0.5 * (1.0 - bench_fold))
	workspace.rotation.z = -PI * 0.5 * (1.0 - bench_fold)
	workspace.visible = bench_fold > 0.01
	landing_hub_visual.visible = bench_fold > 0.01 and state.get("fabrication_hub", {}).get("installed", false)
	if arrival_reveal_caption != null:
		arrival_reveal_caption.text = "SITE PACKAGE UNFOLDING" if arrival_reveal_elapsed >= 1.45 else "FIELD DESCENT IN PROGRESS"
	for panel in machine_root.get_children():
		if not panel.get_meta("arrival_deck_panel", false):
			continue
		var deck_panel := panel as Node3D
		var target: Vector3 = deck_panel.get_meta("arrival_deck_anchor")
		deck_panel.position = arrival_reveal_pod_anchor.lerp(target, fold)
		deck_panel.rotation = Vector3.ZERO
		deck_panel.scale = Vector3(0.22 + 0.78 * fold, 1.0, 0.22 + 0.78 * fold)
		deck_panel.visible = fold > 0.01
	_update_arrival_reveal_camera()
	if character_presenter != null and character_presenter.views.has(client):
		character_presenter.views[client].visible = false

func _update_arrival_reveal_camera() -> void:
	var phase := clampf(arrival_reveal_elapsed / ARRIVAL_REVEAL_SECONDS, 0.0, 1.0)
	phase = phase * phase * (3.0 - 2.0 * phase)
	var back := Vector3(sin(orbit_yaw) * cos(orbit_pitch), sin(orbit_pitch), cos(orbit_yaw) * cos(orbit_pitch))
	var settled_eye := focus + back * distance
	var approach_eye := arrival_reveal_pod_anchor + Vector3(7.0, 17.0, 17.0)
	camera.position = approach_eye.lerp(settled_eye, phase)
	var descent := clampf(arrival_reveal_elapsed / 1.45, 0.0, 1.0)
	var tracked := arrival_reveal_pod_anchor + Vector3.UP * (8.0 * (1.0 - descent) + 0.8)
	var release := smoothstep(0.72, 1.0, arrival_reveal_elapsed / ARRIVAL_REVEAL_SECONDS)
	camera.look_at(tracked.lerp(settled_eye - back, release))

func _advance_arrival_reveal(delta: float) -> void:
	if not arrival_reveal_active:
		return
	arrival_reveal_elapsed = minf(ARRIVAL_REVEAL_SECONDS, arrival_reveal_elapsed + maxf(delta, 0.0))
	_pose_arrival_reveal()
	if arrival_reveal_audio != null:
		arrival_reveal_audio.advance(arrival_reveal_elapsed)
	if arrival_reveal_elapsed >= ARRIVAL_REVEAL_SECONDS:
		_finish_arrival_reveal(false)

func _finish_arrival_reveal(skipped: bool = true) -> void:
	if not arrival_reveal_active:
		return
	if arrival_reveal_audio != null:
		arrival_reveal_audio.finish(skipped)
	_release_character_controls()
	arrival_reveal_elapsed = ARRIVAL_REVEAL_SECONDS
	_pose_arrival_reveal()
	arrival_reveal_active = false
	_sync_landing_pod_visual()
	if character_presenter != null:
		character_presenter.visible = true
	if arrival_gameplay_canvas != null:
		arrival_gameplay_canvas.visible = true
	if arrival_reveal_canvas != null:
		arrival_reveal_canvas.visible = false
	_update_camera()
	_refresh_ui()

func _box(parent: Node, at: Vector3, dimensions: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = dimensions
	mesh.mesh = shape
	mesh.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	if color.a < 1:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh

func _selection_outline() -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var outer := 0.77
	var inner := 0.73
	var strips := [
		[Vector2(-outer, -outer), Vector2(outer, -inner)],
		[Vector2(-outer, inner), Vector2(outer, outer)],
		[Vector2(-outer, -inner), Vector2(-inner, inner)],
		[Vector2(inner, -inner), Vector2(outer, inner)]]
	for strip in strips:
		var low: Vector2 = strip[0]
		var high: Vector2 = strip[1]
		var first := vertices.size()
		vertices.append_array(PackedVector3Array([
			Vector3(low.x, 0, low.y), Vector3(high.x, 0, low.y),
			Vector3(high.x, 0, high.y), Vector3(low.x, 0, high.y)]))
		indices.append_array(PackedInt32Array([first, first + 2, first + 1,
			first, first + 3, first + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var outline := ArrayMesh.new()
	outline.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	marker.mesh = outline
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("b98b3d")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)
	return marker

func _cylinder(parent: Node, at: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 16
	mesh.mesh = shape
	mesh.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh

func _text(parent: Node, words: String, at: Vector3, color: Color, pixel_size: float = 0.007) -> Label3D:
	var label := Label3D.new()
	label.text = words
	label.position = at
	label.font_size = 36
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 3
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)
	return label

func _bar(parent: Node, a: Vector3, b: Vector3, width: float, color: Color) -> void:
	if a.distance_to(b) < 0.01:
		return
	var bar := _box(parent, (a + b) / 2, Vector3(width, width, a.distance_to(b)), color)
	# Both endpoints are local to the parent. A vertical shaft needs a
	# noncollinear up vector, and its orientation must not depend on the tree.
	var direction := (b - a).normalized()
	var up := Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.99 else Vector3.UP
	bar.basis = Basis.looking_at(direction, up)

func _route_segment(parent: Node3D, part_name: String, a: Vector3, b: Vector3,
		width: float, color: Color) -> MeshInstance3D:
	var offset := b - a
	var part := _box(parent, (a + b) / 2.0, Vector3(width, width, offset.length()), color)
	part.name = part_name
	# Material routes join equal-height grid anchors. Local rotation keeps this
	# mesh construction independent of a camera or an attached scene tree.
	part.rotation.y = atan2(offset.x, offset.z)
	return part

func _material_route(parent: Node3D, a: Vector3, b: Vector3) -> Node3D:
	var route := Node3D.new()
	route.name = "MaterialRoute"
	parent.add_child(route)
	if a.distance_to(b) < 0.01:
		return route
	var direction := (b - a).normalized()
	var start := a + direction * 0.55 + Vector3.UP * 0.45
	var finish := b - direction * 0.55 + Vector3.UP * 0.45
	if _native_transmission() and ProductionFeedSleeveArt.mount(route, start, finish):
		return route
	_route_segment(route, "Rail", start, finish, 0.17, Color("929e91"))
	var side := Vector3(-direction.z, 0, direction.x)
	var tip := start.lerp(finish, 0.7) + Vector3.UP * 0.115
	_route_segment(route, "ArrowLeft", tip - direction * 0.15 + side * 0.1, tip,
		0.035, Color("e2c48b"))
	_route_segment(route, "ArrowRight", tip - direction * 0.15 - side * 0.1, tip,
		0.035, Color("e2c48b"))
	return route

func _machine_box(parent: Node3D, part_name: String, at: Vector3, dimensions: Vector3,
		color: Color, metal: float = 0.08, roughness: float = 0.5) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = ProductionVisuals.box_mesh(dimensions)
	part.position = at
	part.name = part_name
	part.material_override = ProductionVisuals.material(color, metal, roughness)
	parent.add_child(part)
	return part

func _machine_cylinder(parent: Node3D, part_name: String, at: Vector3, radius: float,
		height: float, color: Color, orientation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.position = at
	part.rotation = orientation
	part.mesh = ProductionVisuals.cylinder_mesh(radius, height)
	part.material_override = ProductionVisuals.material(color, 0.85, 0.4)
	parent.add_child(part)
	return part

func _machine_axis(entity: Dictionary) -> Vector3:
	# Native projections use the Host's X/Y/Z enumeration. Older projections
	# without an axis retain the original X default.
	return [Vector3.RIGHT, Vector3.UP, Vector3.BACK][int(entity.get("axis", 0))]

func _spindle_rotation(axis: Vector3) -> Vector3:
	if axis == Vector3.UP:
		return Vector3.ZERO
	return Vector3(0, 0, PI / 2) if axis == Vector3.RIGHT else Vector3(PI / 2, 0, 0)

func _machine_drive_stub(anchor: Node3D, entity: Dictionary, press_input: bool = false,
		collector_input: bool = false) -> void:
	if state.get("options", {}).get("native", false):
		var axis := _machine_axis(entity)
		# The vertical stub stays above the base inside the same pick envelope.
		var height := 0.9 if axis == Vector3.UP else 1.35
		var journal := MeshInstance3D.new()
		journal.name = "DriveStub"
		journal.position = Vector3(0, Geometry.ANCHOR_HEIGHT, 0)
		journal.rotation = _spindle_rotation(axis)
		var horizontal_press := press_input and axis != Vector3.UP
		var horizontal_collector := collector_input and axis != Vector3.UP
		journal.mesh = ProductionDriveJournalArt.press_mesh() if horizontal_press or horizontal_collector else ProductionDriveJournalArt.mesh(height)
		journal.material_override = ProductionDriveJournalArt.material()
		anchor.add_child(journal)
		if horizontal_press:
			ProductionDriveJournalArt.mount_press_bearings(anchor, axis)
		if horizontal_collector:
			ProductionDriveJournalArt.mount_collector_bearings(anchor, axis)
	else:
		_machine_cylinder(anchor, "DriveStub", Vector3(0, 0.35, 0.55), 0.085, 0.18,
			Color("b87945"), Vector3(PI / 2, 0, 0))

func _machine_turned(parent: Node3D, part_name: String, at: Vector3,
		profile: PackedVector2Array, color: Color, axis: Vector3 = Vector3.UP) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.position = at
	part.basis = Basis(Quaternion(Vector3.UP, axis))
	part.mesh = ProductionVisuals.turned_mesh(profile)
	part.material_override = ProductionVisuals.material(color, 0.85, 0.38)
	part.set_meta("detail_role", part_name)
	parent.add_child(part)
	return part

func _machine_fastener(parent: Node3D, part_name: String, at: Vector3, normal: Vector3 = Vector3.UP) -> void:
	var assembly := Node3D.new()
	assembly.name = part_name
	assembly.position = at
	assembly.basis = Basis(Quaternion(Vector3.UP, normal))
	assembly.set_meta("surface_detail", true)
	assembly.set_meta("detail_role", part_name)
	parent.add_child(assembly)
	_machine_turned(assembly, "Washer", Vector3.ZERO, PackedVector2Array([
		Vector2(0, 0), Vector2(0.038, 0), Vector2(0.043, 0.002),
		Vector2(0.043, 0.004), Vector2(0.038, 0.006), Vector2(0, 0.006)]), Color("778b8c"))
	var head := MeshInstance3D.new()
	head.name = "HexHead"
	head.position.y = 0.018
	head.mesh = ProductionVisuals.fastener_head_mesh()
	head.material_override = ProductionVisuals.material(Color("b8c3bb"), 0.85, 0.38)
	assembly.add_child(head)
	_machine_box(assembly, "HeadSlot", Vector3(0, 0.03, 0), Vector3(0.03, 0.002, 0.006), Color("28383d"), 0.1, 0.8)

func _machine_surface_detail(machine: Node3D, kind: String) -> void:
	var anchor := Node3D.new()
	anchor.name = "SurfaceDetail"
	machine.add_child(anchor)
	for x in [-0.55, 0.55]:
		for z in [-0.55, 0.55]:
			_machine_fastener(anchor, "FoundationFastener", Vector3(x, 0.24, z))
	match kind:
		"collector":
			var frame: Color = COLORS.collector
			if _native_transmission():
				ProductionCollectorServiceArt.mount(anchor, frame)
			_machine_box(anchor, "ServiceCover", Vector3(-0.22, 0.68, -0.35), Vector3(0.65, 0.5, 0.035), frame.darkened(0.14))
			for n in range(5):
				var vent := _machine_box(anchor, "ServiceVent", Vector3(-0.22, 0.55 + n * 0.06, -0.326), Vector3(0.42, 0.014, 0.006), Color("28383d"), 0.1, 0.8)
				vent.set_meta("detail_role", "ServiceVent")
			for x in [-0.48, 0.04]:
				for y in [0.49, 0.87]:
					_machine_fastener(anchor, "ServiceFastener", Vector3(x, y, -0.32), Vector3.BACK)
			for n in range(8):
				var angle := float(n) * TAU / 8.0
				var tooth := _machine_box(anchor, "CutterFlute",
					Vector3(-0.22 + cos(angle) * 0.235, 1.1 + sin(angle) * 0.235, -0.19),
					Vector3(0.04, 0.045, 0.29), Color("a6b4af"), 0.85, 0.32)
				tooth.rotation.z = angle - PI / 2.0
				tooth.set_meta("detail_role", "CutterFlute")
				if _native_transmission():
					ProductionCollectorToolingArt.mount_flute(tooth)
		"belt":
			if not machine.get_meta("conveyor_frame", false):
				var profile := PackedVector2Array([Vector2(0, -0.025), Vector2(0.11, -0.025),
					Vector2(0.135, -0.015), Vector2(0.135, 0.015), Vector2(0.11, 0.025), Vector2(0, 0.025)])
				for x in [-0.57, 0.57]:
					for side in [-1.0, 1.0]:
						_machine_turned(anchor, "RollerBearing", Vector3(x, 0.465, side * 0.405), profile, Color("778b8c"), Vector3.BACK)
						_machine_fastener(anchor, "BearingFastener", Vector3(x, 0.465, side * 0.435), Vector3.BACK * side)
		"processor":
			var profile := PackedVector2Array([Vector2(0, -0.02), Vector2(0.052, -0.02),
				Vector2(0.065, -0.01), Vector2(0.065, 0.01), Vector2(0.052, 0.02), Vector2(0, 0.02)])
			for x in [-0.34, 0.34]:
				for y in [0.82, 1.32]:
					_machine_turned(anchor, "GuideCollar", Vector3(x, y, -0.19), profile, Color("778b8c"))
			if ProductionPressArt.source_status != "ready":
				for x in [-0.48, 0.48]:
					_machine_box(anchor, "FrameJoint", Vector3(x, 0.46, -0.215), Vector3(0.23, 0.17, 0.035), COLORS.processor.darkened(0.14))
					for y in [0.41, 0.51]:
						_machine_fastener(anchor, "FrameFastener", Vector3(x, y, -0.19), Vector3.BACK)

func _collector_visual(anchor: Node3D, entity: Dictionary = {}) -> void:
	var frame: Color = COLORS.collector
	var steel := Color("a6b4af")
	_machine_box(anchor, "StockBed", Vector3(0, 0.51, 0), Vector3(1.25, 0.1, 0.67), steel, 0.85, 0.45)
	ProductionCollectorArt.mount(anchor, frame)
	var drum := _machine_cylinder(anchor, "CutterDrum", Vector3(-0.22, 1.1, -0.19), 0.24, 0.34,
		Color("465a60"), Vector3(PI / 2, 0, 0))
	var hub := _machine_cylinder(anchor, "CutterHub", Vector3(-0.22, 1.1, 0.01), 0.085, 0.08,
		steel, Vector3(PI / 2, 0, 0))
	if _native_transmission():
		ProductionCollectorToolingArt.mount_body(drum, hub)
		var intake_result: Dictionary = Geometry.collector_intake_boxes(entity)
		if not intake_result.get("accepted", false):
			push_error("The confirmed collector lacks an admitted source-facing intake.")
		elif intake_result.boxes.size() == 1:
			var pickup: Dictionary = intake_result.boxes[0]
			var local_at: Vector3 = pickup.center - anchor.position
			# The open scoop uses the full confirmed pickup box. Its floor meets
			# the rock while the cheeks expose the teeth and lead into the trough.
			_machine_box(anchor, "SourcePickupHousing", local_at + Vector3(0.10, 0, 0),
				Vector3(0.08, 0.20, 0.24), Color("465a60"), 0.85, 0.35)
			_machine_box(anchor, "SourcePickupFloor", local_at + Vector3(0, -0.07, 0),
				Vector3(0.28, 0.045, 0.17), steel, 0.85, 0.42)
			for side in [-1.0, 1.0]:
				_machine_box(anchor, "SourcePickupCheekLeft" if side < 0.0 else "SourcePickupCheekRight",
					local_at + Vector3(-0.02, 0, side * 0.1025),
					Vector3(0.24, 0.20, 0.035), Color("465a60"), 0.85, 0.35)
			for tooth_index in range(3):
				_machine_box(anchor, "SourcePickupTooth%d" % tooth_index,
					local_at + Vector3(-0.105, 0, (tooth_index - 1) * 0.075),
					Vector3(0.06, 0.12, 0.028), steel, 0.85, 0.32)
			var start := Vector3(-0.74, 0.57, local_at.z)
			var finish := Vector3(-0.15, 0.57, 0)
			var delta := finish - start
			var trough := _machine_box(anchor, "SourceGatheringTrough", (start + finish) * 0.5,
				Vector3(delta.length(), 0.045, 0.10), steel, 0.85, 0.45)
			trough.rotation.y = -atan2(delta.z, delta.x)
		elif intake_result.boxes.size() == 9:
			var pickup: Dictionary = intake_result.boxes[0]
			var carrier: Dictionary = intake_result.carrier
			var head: Dictionary = intake_result.head
			var shoe_at: Vector3 = pickup.center - anchor.position
			var carrier_at: Vector3 = carrier.center - anchor.position
			var head_at: Vector3 = head.center - anchor.position
			_machine_box(anchor, "SourceLiftPickup", shoe_at + Vector3(0.04, 0, 0),
				Vector3(0.25, 0.17, 0.35), Color("465a60"), 0.85, 0.35)
			for tooth_index in range(3):
				_machine_box(anchor, "SourceLiftPickupTooth%d" % tooth_index,
					shoe_at + Vector3(-0.13, -0.01, (tooth_index - 1) * 0.12),
					Vector3(0.07, 0.11, 0.035), steel, 0.85, 0.32)
			for index in range(2):
				var guide: Dictionary = intake_result.boxes[index + 1]
				_machine_box(anchor, "SourceLiftGuideLeft" if index == 0 else "SourceLiftGuideRight",
					guide.center - anchor.position, guide.size, frame, 0.8, 0.45)
			var carrier_mesh := ProductionVisuals.prism_mesh(PackedVector2Array([
				Vector2(-0.125, 0.0), Vector2(0.125, 0.0),
				Vector2(0.125, 0.105), Vector2(0.095, 0.105),
				Vector2(0.095, 0.032), Vector2(-0.10, 0.032),
				Vector2(-0.10, 0.055), Vector2(-0.125, 0.055)]), 0.27, 0.002)
			var carrier_finish := ProductionTransmissionFinish.material("worked",
				Color("b1a184"), 0.82, 0.42)
			for index in range(5):
				var flight: Dictionary = intake_result.boxes[index + 3]
				var step := _machine_box(anchor, "SourceLiftFlight%d" % index,
					flight.center - anchor.position - Vector3.UP * Geometry.COLLECTOR_LIFT_PROFILE.flight_raise_y,
					Vector3(flight.size.x, 0.035, flight.size.z), steel, 0.78, 0.42)
				# The formed carrier is inside the same native occupied flight. It
				# stays empty; actual inventory never becomes a decorative ore prop.
				var bucket := MeshInstance3D.new()
				bucket.name = "SourceLiftBucket"
				bucket.mesh = carrier_mesh
				bucket.position.y = 0.018
				bucket.material_override = carrier_finish
				step.add_child(bucket)
				for side in [-1.0, 1.0]:
					_machine_box(step, "SourceLiftBucketCheek", Vector3(0, 0.07, side * 0.138),
						Vector3(0.25, 0.095, 0.024), frame, 0.78, 0.45)
			var start := Vector3(carrier_at.x + 0.03, head_at.y, carrier_at.z)
			var finish := Vector3(0.48, 1.28, 0.28)
			var delta := finish - start
			var discharge := _machine_box(anchor, "SourceLiftDischarge", (start + finish) * 0.5,
				Vector3(delta.length(), 0.07, 0.24), Color("b18a43"), 0.78, 0.46)
			discharge.basis = Basis(Quaternion(Vector3.RIGHT, delta.normalized()))
			var cross := Vector3(-delta.z, 0, delta.x).normalized()
			for side in [-1.0, 1.0]:
				var guard := _machine_box(anchor, "SourceLiftHeadGuardLeft" if side < 0.0 else "SourceLiftHeadGuardRight",
					(start + finish) * 0.5 +
					Vector3(0, 0.10, 0) + cross * side * 0.12,
					Vector3(delta.length(), 0.16, 0.03), frame, 0.8, 0.42)
				guard.basis = discharge.basis
			_machine_box(anchor, "SourceLiftTransferHopper", finish + Vector3(0.03, -0.10, 0),
				Vector3(0.33, 0.20, 0.36), frame, 0.78, 0.48)
			var drop_start := finish + Vector3(0.03, -0.12, 0)
			var stock_entry := Vector3(0.46, 0.65, 0.28)
			var drop_delta := stock_entry - drop_start
			var downspout := _machine_box(anchor, "SourceLiftDownspout",
				(drop_start + stock_entry) * 0.5,
				Vector3(drop_delta.length(), 0.17, 0.18), steel, 0.83, 0.40)
			downspout.basis = Basis(Quaternion(Vector3.RIGHT, drop_delta.normalized()))
	if not (_native_transmission() and ProductionCollectorFeedArt.mount(anchor, frame)):
		for z in [-0.37, 0.37]:
			_machine_box(anchor, "StockGuide", Vector3(0.05, 0.6, z), Vector3(1.15, 0.08, 0.06), frame)
	_machine_drive_stub(anchor, entity, false, true)

func _belt_visual(anchor: Node3D, entity: Dictionary = {}) -> void:
	var frame: Color = COLORS.belt
	# The sourced cast coating is brighter than the legacy flat tint. Keep the
	# finished frame in the same restrained steel palette as nearby machines.
	var fitted_frame := Color("49666a")
	var fitted := _native_transmission() and ProductionConveyorFrameArt.mount(anchor, fitted_frame, int(entity.get("axis", 0)))
	if not fitted:
		for x in [-0.52, 0.52]:
			for z in [-0.36, 0.36]:
				var leg := _machine_box(anchor, "ConveyorLeg", Vector3(x, 0.315, z), Vector3(0.09, 0.21, 0.06), frame)
				leg.set_meta("detail_role", "ConveyorLeg")
	ProductionConveyorArt.mount(anchor)
	if not fitted:
		for z in [-0.36, 0.36]:
			_machine_box(anchor, "ConveyorRail", Vector3(0, 0.57, z), Vector3(1.38, 0.08, 0.05), frame)
			var channel := _machine_box(anchor, "ConveyorChannel", Vector3(0, 0.43, z), Vector3(1.34, 0.08, 0.05), frame)
			channel.set_meta("detail_role", "ConveyorChannel")
	var roller_profile := PackedVector2Array([Vector2(0, -0.35), Vector2(0.055, -0.35),
		Vector2(0.06, -0.345), Vector2(0.06, -0.305), Vector2(0.077, -0.3),
		Vector2(0.077, 0.3), Vector2(0.06, 0.305), Vector2(0.06, 0.345),
		Vector2(0.055, 0.35), Vector2(0, 0.35)])
	for x in [-0.57, 0.57]:
		_machine_turned(anchor, "ConveyorRoller", Vector3(x, 0.465, 0), roller_profile, Color("a6b4af"), Vector3.BACK)
	if not (fitted and ProductionConveyorHubArt.mount(anchor, _machine_axis(entity), fitted_frame)):
		_machine_drive_stub(anchor, entity)

func _press_visual(anchor: Node3D, entity: Dictionary = {}) -> void:
	var frame: Color = COLORS.processor
	var steel := Color("a6b4af")
	var dark := Color("29393f")
	var sourced := ProductionPressArt.mount(anchor)
	if sourced:
		frame = Color("58634c")
	else:
		for x in [-0.48, 0.48]:
			_machine_box(anchor, "PressUpright", Vector3(x, 0.82, -0.38), Vector3(0.15, 1.24, 0.28), frame)
	var fitted_crown := sourced and _native_transmission() and ProductionPressCrownArt.mount(anchor, frame)
	if not fitted_crown:
		_machine_box(anchor, "PressBridge", Vector3(0, 1.5, -0.3), Vector3(1.2, 0.2, 0.36), frame, 0.05 if sourced else 0.08)
	else:
		ProductionPressRearFrameArt.mount(anchor, frame)
	var anvil := _machine_box(anchor, "Anvil", Vector3(0, 0.46, 0.05), Vector3(0.7, 0.16, 0.63), dark)
	var head := _machine_box(anchor, "ToolHead", Vector3(0, 0.84, 0), Vector3(0.56, 0.17, 0.55), steel, 0.85, 0.32)
	if _native_transmission():
		ProductionPressDieArt.mount(anchor, anvil, head)
	_machine_cylinder(anchor, "Piston", Vector3(0, 1.14, -0.08), 0.075, 0.45, steel)
	for x in [-0.34, 0.34]:
		_machine_cylinder(anchor, "ToolGuide", Vector3(x, 1.06, -0.19), 0.04, 0.6, Color("b87945"))
	var tray := _machine_box(anchor, "OutputTray", Vector3(0.46, 0.33, 0.15), Vector3(0.48, 0.05, 0.58), Color("aaa993"), 0.85, 0.5)
	if _native_transmission():
		ProductionPressTrayArt.mount(anchor, tray)
	_machine_drive_stub(anchor, entity, true)
	for x in [-0.48, 0.48]:
		_machine_cylinder(anchor, "BridgeBolt", Vector3(x, 1.5, -0.1075), 0.035, 0.025,
			steel, Vector3(PI / 2, 0, 0))

func _wheel_visual(anchor: Node3D, entity: Dictionary = {}) -> void:
	var frame := Color("465a60")
	var wood := Color("b48c52")
	var native_profile: bool = state.get("options", {}).get("native", false)
	var scale_factor: float = Geometry.ANCHOR_HEIGHT / 0.78 if native_profile else 1.0
	var axis := _machine_axis(entity) if native_profile else Vector3.BACK
	var bearing_rotation := _spindle_rotation(axis)
	if native_profile and ProductionWheelArt.resource_status() == "complete":
		# Preserve the bearing width while raising the shared mechanical center.
		ProductionWheelSupportArt.mount(anchor, axis, 0.5 / 0.78, scale_factor)
	elif native_profile and axis == Vector3.UP:
		# Fixed historical rosters retain the support fitted to their old rim.
		_machine_box(anchor, "WheelStand", Vector3(0, 0.27, 0), Vector3(0.24, 0.3, 0.24), frame)
		_machine_cylinder(anchor, "AxleBearing", Vector3.UP * (Geometry.ANCHOR_HEIGHT - 0.25 * scale_factor),
			0.145 * scale_factor, 0.18 * scale_factor, Color("a6b4af"), bearing_rotation)
	else:
		for side in [-1.0, 1.0]:
			var offset: Vector3 = axis * float(side) * 0.42 * scale_factor
			_machine_box(anchor, "WheelStand", offset + Vector3.UP * 0.51 * scale_factor,
				Vector3(0.16, 0.54, 0.16) * scale_factor, frame)
			_machine_cylinder(anchor, "AxleBearing", offset + Vector3.UP * 0.78 * scale_factor,
				0.145 * scale_factor, 0.18 * scale_factor, Color("a6b4af"), bearing_rotation)
	if native_profile and entity.has("supports"):
		if ProductionWheelPierArt.mount(anchor, entity):
			for child in anchor.get_children():
				if child is MeshInstance3D and child.get_meta("wheel_support_role", "") == "WheelStand":
					child.visible = false
		else:
			push_error("The native wheel support projection is invalid.")
	wheel_rotor = Node3D.new()
	wheel_rotor.name = "WheelRotor"
	wheel_rotor.position = Vector3.UP * (Geometry.ANCHOR_HEIGHT if native_profile else 0.78)
	# Paddle tips use a 0.70-unit source radius. The larger rotor reaches the
	# water while its center stays at the common machine spindle height.
	var rotor_scale := Geometry.WATERWHEEL_RADIUS / 0.70 if native_profile else scale_factor
	var radial_scale := rotor_scale * int(entity.get("tiles", 3)) if native_profile else rotor_scale
	wheel_rotor.scale = Vector3(radial_scale, radial_scale, rotor_scale)
	if native_profile and axis == Vector3.RIGHT:
		wheel_rotor.rotation.y = PI / 2
	elif native_profile and axis == Vector3.UP:
		wheel_rotor.rotation.x = -PI / 2
	anchor.add_child(wheel_rotor)
	var sourced := ProductionWheelArt.mount(wheel_rotor, int(entity.get("tiles", 3)) if native_profile else 3)
	wheel_rotor.set_meta("visual_batch_key", [native_profile, int(entity.get("tiles", 3)), sourced])
	if not sourced:
		var rim_profile := PackedVector2Array([
			Vector2(0.51, -0.022), Vector2(0.518, -0.03), Vector2(0.582, -0.03),
			Vector2(0.59, -0.022), Vector2(0.59, 0.022), Vector2(0.582, 0.03),
			Vector2(0.518, 0.03), Vector2(0.51, 0.022), Vector2(0.51, -0.022)])
		for z in [-0.15, 0.15]:
			_machine_turned(wheel_rotor, "WheelRim", Vector3(0, 0, z), rim_profile, frame, Vector3.BACK)
			for n in range(12):
				var angle := float(n) * TAU / 12.0
				_machine_fastener(wheel_rotor, "RimFastener",
					Vector3(cos(angle) * 0.55, sin(angle) * 0.55, z + signf(z) * 0.03), Vector3.BACK * signf(z))
	# An open rim exposes the spokes. Meshes never supply drive relationships.
	for n in range(12):
		var angle := n * TAU / 12.0
		if not ProductionPaddleArt.mount(wheel_rotor, angle, n, wheel_rotor.scale if native_profile else Vector3.ONE):
			# Historical fixed rosters retain their exact earlier block paddles.
			var radial := Vector3(cos(angle), sin(angle), 0)
			var paddle := _machine_box(wheel_rotor, "WheelPaddle", radial * 0.62,
				Vector3(0.14, 0.16, 0.28), wood, 0.05, 0.88)
			paddle.rotation.z = angle
	if not sourced:
		for n in range(3):
			var spoke := _machine_box(wheel_rotor, "WheelSpoke", Vector3.ZERO,
				Vector3(0.065, 1.0, 0.085), wood, 0.05, 0.88)
			spoke.rotation.z = n * PI / 3.0
	var journal := _machine_cylinder(wheel_rotor, "WheelHub", Vector3.ZERO, 0.13, 0.45,
		Color("b87945"), Vector3(PI / 2, 0, 0))
	if native_profile:
		# Bake the fitted journal in metres, then cancel the rotor's scale.
		# Its local worked-metal repeat stays physical as the rim grows.
		journal.mesh = ProductionDriveJournalArt.mesh(0.45 * rotor_scale, 0.13 * 0.5 / 0.78)
		journal.material_override = ProductionDriveJournalArt.material()
		journal.scale = Vector3(1.0 / radial_scale, 1.0 / rotor_scale, 1.0 / radial_scale)

func _material_rotated(_entity_id: String, entity: Dictionary) -> bool:
	return _native_transmission() and entity.get("kind") == "belt" and int(entity.get("axis", 2)) == 0

func _assemble_machine(anchor: Node3D, entity: Dictionary, rotated := false) -> void:
	anchor.set_meta("material_rotated", rotated)
	var facing: int = int(entity.get("rotation", 0)) if _native_transmission() and entity.kind in ["collector", "processor"] else 0
	if facing != 0 and entity.kind != "collector":
		var visual := Node3D.new()
		visual.name = "RotatedMachineVisual"
		visual.rotation.y = -float(facing) * PI / 2.0
		anchor.add_child(visual)
		var local_entity := entity.duplicate()
		local_entity["rotation"] = 0
		if facing % 2 == 1 and int(entity.get("axis", 0)) != 1:
			local_entity["axis"] = 2 - int(entity.get("axis", 0))
		_assemble_machine(visual, local_entity)
		return
	if rotated:
		var visual := Node3D.new()
		visual.name = "RotatedMachineVisual"
		visual.rotation.y = -PI / 2.0
		anchor.add_child(visual)
		var local_entity := entity.duplicate()
		if int(entity.get("axis", 0)) == 0:
			local_entity["axis"] = 2
		elif int(entity.get("axis", 0)) == 2:
			local_entity["axis"] = 0
		_assemble_machine(visual, local_entity)
		return
	var water_wheel: bool = entity.kind == "wheel" and _native_transmission()
	if not water_wheel:
		var plinth := MeshInstance3D.new()
		plinth.name = "Plinth"
		plinth.position = Vector3(0, 0.12, 0)
		plinth.mesh = ProductionSkidArt.skid_mesh()
		plinth.material_override = ProductionVisuals.material(Color("273c41"), 0.08, 0.5)
		plinth.set_meta("asset_role", "MachineSupportSkid")
		anchor.add_child(plinth)
	match entity.kind:
		"collector":
			_collector_visual(anchor, entity)
			if _native_transmission():
				ProductionCollectorOutputArt.mount(anchor, facing)
		"belt": _belt_visual(anchor, entity)
		"processor": _press_visual(anchor, entity)
		"wheel": _wheel_visual(anchor, entity)
	if not water_wheel:
		_machine_surface_detail(anchor, entity.kind)

func _prime_machine_visuals() -> void:
	# Build once during opening setup so the first tool selection can reuse
	# imported textures, procedural meshes, and their Godot render resources.
	var previous_rotor := wheel_rotor
	for kind in ["collector", "belt", "processor", "wheel"]:
		var anchor := Node3D.new()
		var cell := [0, 1] if kind == "collector" else [1, 2]
		anchor.position = _cell_position(cell)
		_assemble_machine(anchor, {"kind": kind, "axis": 0, "tiles": 3,
			"rotation": 0, "cell": cell, "level": 0})
		anchor.free()
	wheel_rotor = previous_rotor

func _collector_preview_source_path(cell: Vector2i, level: int) -> String:
	return "res://opening/assets/prebuilt-preview-collector-source-%d-%d.scn" % [cell.y, level]

func _prefetch_machine_preview_variants() -> void:
	# Load during the arrival reveal, after the workshop cover is gone. Spread
	# requests over frames; no variant is built on the selection frame.
	var paths: Array[String] = []
	for site in [0, 1]:
		for level in [0, 4, 8]:
			paths.append(_collector_preview_source_path(Vector2i(0, site), level))
	for axis in [1, 2]:
		paths.append("res://opening/assets/prebuilt-preview-processor-drive-%d.scn" % axis)
		paths.append("res://opening/assets/prebuilt-preview-belt-axis-%d.scn" % axis)
	for axis in [1, 2]:
		paths.append("res://opening/assets/prebuilt-preview-wheel-support-%d.scn" % axis)
	for tiles in range(4, BAKED_WHEEL_PREVIEW_MAX_TILES + 1):
		paths.append("res://opening/assets/prebuilt-preview-wheel-rotor-%d.scn" % tiles)
	preview_prefetch_complete = false
	for index in paths.size():
		if not is_inside_tree():
			return
		var path: String = paths[index]
		if ResourceLoader.load_threaded_request(path) == OK:
			preview_prefetch_paths.append(path)
		else:
			push_error("Cannot prepare a machine preview resource: " + path)
		if index % 4 == 3:
			await get_tree().process_frame
	call_deferred("_finish_machine_preview_prefetch")

func _finish_machine_preview_prefetch() -> void:
	while is_inside_tree() and not preview_prefetch_paths.is_empty():
		var remaining: Array[String] = []
		for path in preview_prefetch_paths:
			if packed_preview_templates.has(path):
				continue
			var status := ResourceLoader.load_threaded_get_status(path)
			if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				remaining.append(path)
			elif status == ResourceLoader.THREAD_LOAD_LOADED:
				packed_preview_templates[path] = ResourceLoader.load_threaded_get(path)
			else:
				push_error("Cannot load a machine preview resource: " + path)
		preview_prefetch_paths = remaining
		if not preview_prefetch_paths.is_empty():
			await get_tree().process_frame
	if is_inside_tree():
		# Prime the shared mesh and UV caches during the arrival reveal. Later
		# wheel sizes use the same loaded source art and stay off the cold path.
		var large_wheel := _packed_machine_preview_variant("wheel", 2, 10, 0, Vector2i(1, 2), 4)
		if large_wheel != null:
			large_wheel.free()
		else:
			push_error("Cannot prepare the large-wheel preview geometry.")
	preview_prefetch_complete = preview_prefetch_paths.is_empty()

func _packed_preview_resource(path: String) -> PackedScene:
	if packed_preview_templates.has(path):
		return packed_preview_templates[path]
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		preview_variant_pending = true
		return null
	var packed := (ResourceLoader.load_threaded_get(path) if status == ResourceLoader.THREAD_LOAD_LOADED
		else load(path)) as PackedScene
	if packed != null:
		packed_preview_templates[path] = packed
	return packed

func _clear_preview_owners(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_preview_owners(child)

func _replace_preview_parts(anchor: Node3D, replacement: PackedScene, prefixes: Array[String]) -> void:
	var first := -1
	for child in anchor.get_children():
		var replace := false
		for prefix in prefixes:
			if child.name.begins_with(prefix):
				replace = true
				break
		if replace:
			if first < 0:
				first = child.get_index()
			child.free()
	var prepared := replacement.instantiate() as Node3D
	for child in prepared.get_children():
		_clear_preview_owners(child)
		prepared.remove_child(child)
		anchor.add_child(child)
		if first >= 0:
			anchor.move_child(child, first)
			first += 1
	prepared.free()

func _rotate_packed_preview_port(anchor: Node3D, facing: int) -> void:
	if facing == 0:
		return
	var turn := Transform3D(Basis(Vector3.UP, -float(facing) * PI / 2.0), Vector3.ZERO)
	for child in anchor.get_children():
		if child.name.begins_with("PortArrow") or child.name == "MaterialPortLabel":
			child.transform = turn * child.transform
			if child.name == "MaterialPortLabel":
				child.set_meta("port_side", turn.basis * child.get_meta("port_side", Vector3.ZERO))

func _resize_packed_wheel_rotor(rotor: Node3D, tiles: int) -> void:
	# The packed three-tile wheel already owns its materials and paddle nodes.
	# Reuse them rather than preparing GLTF and textures on the click frame.
	var rim := rotor.get_node("SourcedTimberRimN") as MeshInstance3D
	var centre := rotor.get_node("SourcedTimberRotor") as MeshInstance3D
	var sized_rim := ProductionWheelArt._sized_mesh(rim.mesh as ArrayMesh, tiles, true)
	var sized_centre := ProductionWheelArt._sized_mesh(centre.mesh as ArrayMesh, tiles, false)
	var rotor_scale := Geometry.WATERWHEEL_RADIUS / 0.70
	var radial_scale := rotor_scale * tiles
	var physical_scale := Vector3(radial_scale, radial_scale, rotor_scale)
	rotor.scale = physical_scale
	centre.mesh = sized_centre
	rim.mesh = sized_rim
	(rotor.get_node("SourcedTimberRimP") as MeshInstance3D).mesh = sized_rim
	(rotor.get_node("WheelHub") as MeshInstance3D).scale = Vector3(
		1.0 / radial_scale, 1.0 / rotor_scale, 1.0 / radial_scale)
	for child in rotor.get_children():
		if not child is MeshInstance3D or child.get_meta("detail_role", "") != "WheelPaddle":
			continue
		var blade := child as MeshInstance3D
		blade.mesh = ProductionPaddleArt.timber_mesh(Vector3(0.14, 0.018, 0.28), physical_scale)
		for part in blade.get_children():
			if not part is MeshInstance3D:
				continue
			match part.get_meta("detail_role", ""):
				"PaddleRootCleat":
					part.mesh = ProductionPaddleArt.timber_mesh(Vector3(0.04, 0.06, 0.10), physical_scale)
				"PaddleEdgeRib":
					part.mesh = ProductionPaddleArt.timber_mesh(Vector3(0.12, 0.038, 0.018), physical_scale)
				"PaddleWearStrip":
					part.position.y = 0.009 + 0.004 / physical_scale.y
					part.scale = Vector3(1.0 / physical_scale.x, 1.0 / physical_scale.y, 1.0)
				"PaddleBolt":
					part.position.y = -0.036 - 0.005 / physical_scale.y
					part.scale = Vector3.ONE / physical_scale
	rotor.set_meta("visual_batch_key", [true, tiles, true])

func _packed_machine_preview_variant(kind: String, axis: int, tiles: int,
		facing: int, cell: Vector2i, level: int) -> Node3D:
	preview_variant_pending = false
	if not _native_transmission():
		return null
	if kind == "wheel":
		var default_wheel: PackedScene = packed_preview_templates.get("wheel")
		if default_wheel == null:
			default_wheel = load("res://opening/assets/prebuilt-preview-wheel.scn") as PackedScene
		if default_wheel == null:
			return null
		var support_part: PackedScene
		if axis != 0:
			support_part = _packed_preview_resource(
				"res://opening/assets/prebuilt-preview-wheel-support-%d.scn" % axis)
			if support_part == null:
				return null
		var rotor_part: PackedScene
		if tiles != 3 and tiles <= BAKED_WHEEL_PREVIEW_MAX_TILES:
			rotor_part = _packed_preview_resource(
				"res://opening/assets/prebuilt-preview-wheel-rotor-%d.scn" % tiles)
			if rotor_part == null:
				return null
		var wheel := default_wheel.instantiate() as Node3D
		if support_part != null:
			for child in wheel.get_children():
				if child.name != "WheelRotor":
					child.free()
			var prepared := support_part.instantiate() as Node3D
			for child in prepared.get_children():
				_clear_preview_owners(child)
				prepared.remove_child(child)
				wheel.add_child(child)
				wheel.move_child(child, wheel.get_node("WheelRotor").get_index())
			prepared.free()
		if rotor_part != null:
			_replace_preview_parts(wheel, rotor_part, ["WheelRotor"])
		var rotor := wheel.get_node("WheelRotor") as Node3D
		if tiles > BAKED_WHEEL_PREVIEW_MAX_TILES:
			_resize_packed_wheel_rotor(rotor, tiles)
		if axis == 1:
			rotor.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
		elif axis == 2:
			rotor.rotation = Vector3.ZERO
		return wheel
	if kind == "belt":
		var belt_path := ("res://opening/assets/prebuilt-preview-belt.scn" if axis == 0
			else "res://opening/assets/prebuilt-preview-belt-axis-%d.scn" % axis)
		var belt: PackedScene = _packed_preview_resource(belt_path)
		return belt.instantiate() as Node3D if belt != null else null
	if kind not in ["collector", "processor"]:
		return null
	var default: PackedScene = packed_preview_templates.get(kind)
	if default == null:
		default = load("res://opening/assets/prebuilt-preview-" + kind + ".scn") as PackedScene
	if default == null:
		return null
	var anchor := default.instantiate() as Node3D
	if kind == "collector":
		if cell != Vector2i(0, 1) or level != 0:
			if cell.x == 0 and cell.y in [0, 1]:
				var source: PackedScene = _packed_preview_resource(_collector_preview_source_path(cell, level))
				if source == null:
					anchor.free()
					return null
				_replace_preview_parts(anchor, source, ["Source"])
			else:
				for child in anchor.get_children():
					if child.name == "Source":
						child.free()
		var drive := anchor.get_node("DriveStub") as MeshInstance3D
		if axis == 1:
			for child in anchor.get_children():
				if child.name.begins_with("CollectorInput"):
					child.free()
			drive.mesh = ProductionDriveJournalArt.mesh(0.9)
			drive.rotation = Vector3.ZERO
		elif axis == 2:
			var turn := Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3.ZERO)
			for child in anchor.get_children():
				if child.name == "DriveStub" or child.name.begins_with("CollectorInput"):
					child.transform = turn * child.transform
					if child.name == "DriveStub":
						child.rotation = _spindle_rotation(Vector3.BACK)
					elif child.name.begins_with("CollectorInputBearing"):
						child.basis = Basis(Quaternion(Vector3.UP, Vector3.BACK))
					elif child.name.begins_with("CollectorInputPost"):
						child.basis = Basis.IDENTITY
						child.mesh = ProductionVisuals.box_mesh(Vector3(0.16, 0.50, 0.08))
					elif child.name.begins_with("CollectorInputFoot"):
						child.basis = Basis.IDENTITY
						child.mesh = ProductionVisuals.box_mesh(Vector3(0.20, 0.10, 0.26))
		var cassette := anchor.get_node_or_null("CollectorOutputCassette") as Node3D
		if cassette != null:
			cassette.rotation.y = -float(facing) * PI / 2.0
		_rotate_packed_preview_port(anchor, facing)
		return anchor
	var local_axis := 2 - axis if facing % 2 == 1 and axis != 1 else axis
	if local_axis != 0:
		var drive_part: PackedScene = _packed_preview_resource(
			"res://opening/assets/prebuilt-preview-processor-drive-%d.scn" % local_axis)
		if drive_part == null:
			anchor.free()
			return null
		_replace_preview_parts(anchor, drive_part, ["DriveStub", "PressInput"])
		# Press bearings follow the drive stub in the source assembly.
		# The drive resource owns their complete alternative layout.
	if facing != 0:
		var holder := Node3D.new()
		holder.name = "RotatedMachineVisual"
		for child in anchor.get_children():
			if child.name.begins_with("PortArrow") or child.name == "MaterialPortLabel":
				continue
			_clear_preview_owners(child)
			anchor.remove_child(child)
			holder.add_child(child)
		holder.rotation.y = -float(facing) * PI / 2.0
		anchor.add_child(holder)
		anchor.move_child(holder, 0)
		_rotate_packed_preview_port(anchor, facing)
	return anchor

func _warm_packed_machine_previews() -> void:
	if DisplayServer.get_name() == "headless":
		for kind in ["collector", "belt", "processor", "wheel"]:
			packed_preview_templates[kind] = load("res://opening/assets/prebuilt-preview-" + kind + ".scn")
		return
	var cover := CanvasLayer.new()
	cover.name = "MachinePreviewWarmup"
	cover.layer = 100
	var color := ColorRect.new()
	color.color = Color("101e20")
	color.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.add_child(color)
	var progress := Label.new()
	progress.text = "Preparing workshop..."
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	progress.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.add_child(progress)
	add_child(cover)
	var view_size := get_viewport().get_visible_rect().size
	for index in 4:
		var kind: String = ["collector", "belt", "processor", "wheel"][index]
		var packed: PackedScene = load("res://opening/assets/prebuilt-preview-" + kind + ".scn")
		if packed == null:
			continue
		packed_preview_templates[kind] = packed
		var anchor := packed.instantiate() as Node3D
		add_child(anchor)
		_style_machine_preview(anchor)
		anchor.position = camera.project_position(Vector2(view_size.x * (0.2 + 0.2 * index), view_size.y * 0.5), 7.0)
		packed_preview_nodes[kind] = anchor
	var foundation := Node3D.new()
	foundation.name = "FoundationPreviewTemplate"
	add_child(foundation)
	_assemble_foundation(foundation)
	_style_machine_preview(foundation)
	foundation.position = camera.project_position(view_size * Vector2(0.5, 0.65), 7.0)
	packed_preview_nodes["foundation"] = foundation
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	for anchor in packed_preview_nodes.values():
		anchor.visible = false
	await _warm_transmission_placement_previews(view_size)
	var frames_waited := 0
	while not state.get("actors", {}).get(client, {}).get("ready", false) and frames_waited < 120:
		frames_waited += 1
		await get_tree().process_frame
	if state.get("actors", {}).get(client, {}).get("ready", false):
		# Draw the real tool panels behind the loading cover. Arrival has no
		# carried kits yet, so only the temporary visual form is shown here.
		var opening_message := status_label.text
		var opening_refused := status_refused
		var resume_processing := is_processing()
		set_process(false)
		for kind in ["collector", "foundation", "processor", "wheel"]:
			var anchor: Node3D = packed_preview_nodes.get(kind)
			if anchor == null:
				continue
			_select_tool(kind)
			_choose_machine_preview(anchor)
			anchor.visible = true
			_refresh_placement_options()
			await RenderingServer.frame_post_draw
			anchor.visible = false
		_select_tool("inspect")
		set_process(resume_processing)
		_message(opening_message, opening_refused)
	cover.free()
	# The first native input window follows the arrival reveal. Begin loading
	# finite variants now, after the covered startup is complete.
	_prefetch_machine_preview_variants()

func _warm_transmission_placement_previews(view_size: Vector2) -> void:
	# Draw the two cog sizes and the shaft while the workshop cover is visible.
	# Their shared meshes and render resources then exist before a tool click.
	var assets = load("res://opening/native_transmission_assets.gd")
	var warm_nodes: Array[Node3D] = []
	for teeth in [2, 4]:
		var cog := MeshInstance3D.new()
		cog.name = "CogPreviewWarmup%d" % teeth
		cog.mesh = assets.complete_gear_mesh(PITCH / 2.0, teeth, Color("687a7b"), PITCH)
		cog.position = camera.project_position(Vector2(view_size.x * (0.2 if teeth == 2 else 0.8),
			view_size.y * 0.5), 7.0)
		add_child(cog)
		_style_machine_preview(cog)
		warm_nodes.append(cog)
	var shaft := Node3D.new()
	shaft.name = "ShaftPreviewWarmup"
	shaft.position = camera.project_position(view_size * Vector2(0.5, 0.5), 7.0)
	add_child(shaft)
	assets.shaft(shaft, PITCH, Color("687a7b"))
	_style_machine_preview(shaft)
	warm_nodes.append(shaft)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	for node in warm_nodes:
		node.free()

func _choose_machine_preview(pooled: Node3D = null) -> void:
	var desired := pooled
	if desired == null:
		if mutable_machine_preview == null:
			mutable_machine_preview = Node3D.new()
			mutable_machine_preview.name = "MachinePlacementPreview"
			add_child(mutable_machine_preview)
		desired = mutable_machine_preview
	if machine_preview != desired:
		if machine_preview != null:
			machine_preview.visible = false
		machine_preview = desired
		machine_preview_key = ""

# Paddle joinery ends by 32 m with a 2 m fade margin; the extra room
# covers the largest authored rim and a camera move between render cuts.
const WHEEL_DETAIL_UPDATE_RADIUS := 48.0
const WHEEL_MOTION_VISIBILITY_MARGIN := 16.0
# Bound moving rotor batches by worksite region so distant wheels do not
# submit the complete field to the color and shadow passes.

func _index_machine_rotors() -> void:
	machine_rotor_cells.clear()
	var cell_indices := {}
	for wheel in machine_rotors:
		var center: Vector3 = wheel.center
		var key := Vector3i(floori(center.x / MachineBatcher.WHEEL_ROTOR_BATCH_CELL),
			floori(center.y / MachineBatcher.WHEEL_ROTOR_BATCH_CELL), floori(center.z / MachineBatcher.WHEEL_ROTOR_BATCH_CELL))
		if not cell_indices.has(key):
			cell_indices[key] = machine_rotor_cells.size()
			machine_rotor_cells.append({"bounds": AABB(center, Vector3.ZERO), "wheels": [wheel]})
		else:
			var cell: Dictionary = machine_rotor_cells[cell_indices[key]]
			cell.bounds = (cell.bounds as AABB).expand(center)
			cell.wheels.append(wheel)

func _rebuild_machines() -> void:
	_sync_machine_body_context()
	machine_rotors.clear()
	machine_motion_anchors.clear()
	machine_batches.machine_cutter_batch_slots.clear()
	var foundation_masks := ProductionFoundationArt.neighbor_masks(state.get("foundations", {}))
	var scenery := get_node_or_null("ProductionScenery")
	if scenery != null and ProductionEnvironment.Surface != null:
		ProductionEnvironment.refresh_vegetation(scenery, state)
	for child in machine_root.get_children():
		child.free()
	wheel_rotor = null
	for id in state.get("foundations", {}):
		var surface: Dictionary = state.foundations[id]
		var anchor := Node3D.new()
		anchor.position = _entity_position(surface)
		anchor.set_meta("arrival_deck_panel", str(id).begins_with("pod-floor-"))
		anchor.set_meta("arrival_deck_anchor", anchor.position)
		machine_root.add_child(anchor)
		_assemble_foundation(anchor, foundation_masks[id])
		var body := StaticBody3D.new()
		body.collision_layer = Geometry.PICK_LAYER
		body.collision_mask = 0
		body.set_meta("entity", id)
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3.ONE * PITCH
		collider.shape = shape
		collider.position.y = -PITCH / 2.0
		body.add_child(collider)
		anchor.add_child(body)
	for entity_id in state.entities:
		var entity: Dictionary = state.entities[entity_id]
		var kind: String = entity.kind
		var anchor := Node3D.new()
		anchor.position = _entity_position(entity)
		machine_root.add_child(anchor)
		_assemble_machine(anchor, entity, _material_rotated(entity_id, entity))
		if kind == "wheel" and wheel_rotor != null:
			# A detached presentation fixture has no global transform yet.
			var rotor_center: Vector3 = wheel_rotor.global_position if wheel_rotor.is_inside_tree() \
				else machine_root.transform * anchor.transform * wheel_rotor.position
			machine_rotors.append({"id": entity_id, "rotor": wheel_rotor,
				"base": wheel_rotor.basis, "center": rotor_center})
		anchor.set_meta("machine_entity", entity_id)
		anchor.set_meta("machine_kind", kind)
		if kind in ["collector", "belt", "processor"]:
			machine_motion_anchors.append(anchor)
		var motion_meshes: Array[Dictionary] = []
		_remember_machine_motion(anchor, kind, Transform3D.IDENTITY, motion_meshes)
		anchor.set_meta("motion_meshes", motion_meshes)
		if kind == "collector" and transmission_presenter != null:
			_apply_cutter_pose(anchor, motion_meshes, transmission_presenter.visual_angle(entity_id))
		elif kind == "belt" and transmission_presenter != null:
			_apply_conveyor_motion(anchor, transmission_presenter.visual_rotation(entity_id))
		elif kind == "processor" and _native_transmission():
			var target: Variant = _observed_press_target()
			var generation: Variant = entity.get("generation")
			if target != null and typeof(generation) == TYPE_INT and generation > 0:
				if not machine_press_poses.has(entity_id):
					machine_press_poses[entity_id] = {"generation": generation, "travel": target}
				_apply_press_pose(motion_meshes, machine_press_poses[entity_id].travel)
		var body := StaticBody3D.new()
		body.collision_layer = Geometry.PICK_LAYER
		body.collision_mask = 0
		body.set_meta("entity", entity_id)
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Geometry.wheel_half_extents(int(entity.get("axis", 0)), int(entity.get("tiles", 3))) * 2.0 if kind == "wheel" and _native_transmission() else Vector3(Geometry.MACHINE_SIZE[0], Geometry.MACHINE_SIZE[1], Geometry.MACHINE_SIZE[2])
		collider.shape = shape
		collider.position.y = Geometry.ANCHOR_HEIGHT if kind == "wheel" and _native_transmission() else Geometry.MACHINE_CENTER_HEIGHT
		body.add_child(collider)
		if kind == "collector" and _native_transmission():
			var intake_result: Dictionary = Geometry.collector_intake_boxes(entity)
			if not intake_result.get("accepted", false):
				push_error("The collector pick geometry lacks its native source-facing intake.")
			else:
				for intake: Dictionary in intake_result.boxes:
					var intake_pick := CollisionShape3D.new()
					var intake_box := BoxShape3D.new()
					intake_box.size = intake.size
					intake_pick.shape = intake_box
					intake_pick.position = intake.center - anchor.position
					body.add_child(intake_pick)
		if kind == "wheel" and _native_transmission() and entity.has("supports"):
			var support_result: Dictionary = Geometry.wheel_support_boxes(entity)
			if not support_result.get("accepted", false):
				push_error("The wheel pick geometry lacks its native support boxes.")
			else:
				for support: Dictionary in support_result.boxes:
					var support_pick := CollisionShape3D.new()
					var support_box := BoxShape3D.new()
					support_box.size = support.size
					support_pick.shape = support_box
					support_pick.position = support.center - anchor.position
					body.add_child(support_pick)
		anchor.add_child(body)
		var caption_height := collider.position.y + shape.size.y * 0.5 + 0.275
		var caption := _text(anchor, NAMES.get(kind, kind).to_upper(), Vector3(0, caption_height, 0), Color("f2e5c5"))
		caption.name = "MachineCaption"
		caption.visible = not _native_transmission()
	for pair in state.links:
		if state.entities.has(pair[0]) and state.entities.has(pair[1]):
			_material_route(machine_root, _entity_position(state.entities[pair[0]]),
				_entity_position(state.entities[pair[1]]))
	for pair in state.get("drive_links", []):
		if not _native_transmission() and state.entities.has(pair[0]) and state.entities.has(pair[1]):
			_bar(machine_root, _cell_position(state.entities[pair[0]].cell) + Vector3(0, 0.35, 0.55),
				_cell_position(state.entities[pair[1]].cell) + Vector3(0, 0.35, 0.55), 0.09, Color("d1b56e"))
	_index_machine_rotors()
	machine_batches.rebuild(machine_root, machine_motion_anchors, _native_transmission(),
		model is NativeWorldModel and state.get("placed_components", {}).size() >= 12)

func _redraw_items() -> void:
	# The asset helper uses this script's shared surfaces, so load it after
	# the opening class is available instead of creating a preload cycle.
	if workpiece_item_assets == null:
		workpiece_item_assets = load("res://opening/workpiece_item_assets.gd")
	workpiece_item_assets.populate_items(item_root, state, PITCH)

func _refresh() -> void:
	_refresh_from_projection(model._view_projection_borrowed() if model.has_method("_view_projection_borrowed") \
		else model.view_projection() if model.has_method("view_projection") else model.projection())

func _refresh_from_projection(known_projection: Dictionary) -> void:
	# Both model paths return the complete projection from advance(). Reuse the
	# final accepted tick in this render cut instead of projecting every part
	# again. A failed tick or a frame without one still reads current authority.
	var prior_cut: Dictionary = state.get("manual_cuts", {}).get(client, {})
	var prior_cargo: Dictionary = state.get("cargo", {}).get(client, {})
	state = known_projection
	if not prior_cut.is_empty() and not state.get("manual_cuts", {}).has(client):
		var current_cargo: Dictionary = state.get("cargo", {}).get(client, {})
		var timber_added: int = int(current_cargo.get("timber", 0)) - int(prior_cargo.get("timber", 0))
		var raw_added: int = int(current_cargo.get("raw", 0)) - int(prior_cargo.get("raw", 0))
		_message(_harvest_result_text({"moved_timber": timber_added, "moved_raw": raw_added}) \
			if timber_added > 0 or raw_added > 0 else "Cut interrupted.")
	_sync_landing_pod_visual()
	# Shared profiles arrive after presenter creation. Choose this revisable
	# default once, preserving any pitch already adjusted while connecting.
	if not native_camera_initialized and _native_transmission():
		native_camera_initialized = true
		if orbit_pitch == 0.82:
			orbit_pitch = 0.60
	var next_key: String
	if model is NativeWorldModel and typeof(state.get("order")) == TYPE_INT and typeof(state.get("context")) == TYPE_STRING:
		# Commands can change topology; material ticks advance revision without
		# changing the built geometry. A new model or context also needs a rebuild.
		next_key = "native:" + str(model.get_instance_id()) + ":" + state.context + ":" + str(state.order)
	else:
		next_key = JSON.stringify([state.entities, state.links, state.get("drive_links", []), state.get("foundations", {})])
	if next_key != geometry_key:
		geometry_key = next_key
		if actor_world != null:
			actor_world.sync_topology(state)
		_rebuild_machines()
	if int(state.revision) != visual_revision:
		visual_revision = int(state.revision)
		var next_item_key := [state.get("context"), state.get("order"), state.get("stock"),
			state.get("hand_sources", {}).get(str(state.get("source_deposit", {}).get("id", "")) + "-region-4", {}).get("remaining")]
		if not model is NativeWorldModel or next_item_key != item_visual_key:
			item_visual_key = next_item_key
			_redraw_items()
		if _native_transmission() and transmission_presenter != null:
			transmission_presenter.refresh()
	if character_presenter != null:
		character_presenter.refresh()
	if not model is NativeWorldModel or _native_ui_key() != ui_refresh_key:
		_refresh_ui()

func _native_ui_key() -> Array:
	return [model.get_instance_id(), state.get("context"), state.get("order"),
		state.get("stock"), state.get("remaining"), state.get("line_belt_raw"),
		state.get("inventories"), state.get("cargo", {}).get(client),
		state.get("manual_cuts", {}).get(client), state.get("dropped_material"),
		state.get("belt_spans"), state.get("opening_engineering"),
		state.get("actors", {}).get(client, {}).get("ready", false),
		selected, mode, explanation_open, startup_save_pending, save_slot_ready, save_slot_owned,
		building_rotation, foundation_level, wheel_level, wheel_tiles,
		transmission_controls.active_tool if transmission_controls != null else "",
		transmission_controls.selected_axis if transmission_controls != null else ""]

func _display_parts() -> Dictionary:
	if state.get("options", {}).get("native", false):
		return state.get("part_kits", {}).get(client, {})
	return state.get("parts", {})

func _parts_are_shared() -> bool:
	return false

func _confirmed_drive_status(motion: Variant) -> String:
	if not motion is Dictionary or motion.is_empty():
		return "Power status unavailable"
	if motion.get("state") == "rotating":
		if typeof(motion.get("numerator")) != TYPE_INT or typeof(motion.get("denominator")) != TYPE_INT or motion.denominator <= 0:
			return "Power status unavailable"
		var description := "Rate %d / %d" % [motion.numerator, motion.denominator]
		if motion.has("capacity"):
			description += "\nLoad %.2f / capacity %.2f" % [motion.get("impact", 0.0), motion.capacity]
		return description
	elif motion.get("overloaded", false):
		var description := "Overloaded · load %.2f / capacity %.2f" % [motion.get("impact", 0.0), motion.get("capacity", 0.0)]
		var limiting: Variant = motion.get("limiting_part", "")
		if limiting is String and not limiting.is_empty():
			var part_kind: String = str(motion.get("limiting_kind", "drive part")).replace("_", " ").capitalize()
			description += "\nLimit: %s (%s). Replace with copper or split the load." % [part_kind, limiting]
		else:
			description += "\nAdd power or reduce load."
		return description
	return str(motion.get("state", "disconnected")).capitalize()

func _transmission_inspection(part: Dictionary, motion: Dictionary) -> String:
	var name := "Shaft"
	if part.kind == "gear":
		name = {2: "Small Cogwheel", 4: "Large Cogwheel"}.get(part.get("teeth"), "Cogwheel")
	elif part.kind == "gearbox":
		name = "Horizontal Gearbox"
	elif part.kind == "vertical_gearbox":
		name = "Vertical Gearbox"
	elif part.kind == "chain_drive":
		name = "Encased Chain Drive · link %s" % ["X", "Y", "Z"][part.get("relay_axis", 0)]
	return "%s · %s axis\nGrid %s\n%s" % [name, ["X", "Y", "Z"][part.axis], str(part.center), _confirmed_drive_status(motion)]

func _machine_inspection(entity: Dictionary, stock: Dictionary, motion: Variant, native: bool) -> String:
	var description := "%s\nSquare %s" % [NAMES.get(entity.kind, entity.kind), str(entity.cell)]
	if entity.kind == "processor":
		description += "\n%d in · %d held · %d ready" % [stock.get("input", 0), stock.get("held", 0), stock.get("output", 0)]
	if native:
		description += "\n" + _confirmed_drive_status(motion)
	return description

func _belt_inspection(span: Dictionary, motions: Dictionary) -> String:
	var occupied := 0
	for slot: Variant in span.get("slots", []):
		if slot is Dictionary:
			occupied += 1
	var drive: Variant = motions.get(span.get("from", ""))
	return "Mechanical belt\n%d occupied %s\n%s\nRecover contents before dismantling." % [occupied, "position" if occupied == 1 else "positions", _confirmed_drive_status(drive)]

func _refresh_ui() -> void:
	_refresh_hand_trees()
	_refresh_ore_field()
	if stock_label == null:
		return
	if _object_menu_open() and not _contains_target(state, object_menu_target):
		object_menu.hide()
		return
	_refresh_transmission()
	var inventory := int(state.inventories.get(client, 0))
	parts_label.text = "BUILD / INVENTORY"
	goal_text = "FIRST SHIFT\nBring back 4 plates\n%d / 4 collected" % inventory
	var belt_raw: int = int(state.get("line_belt_raw", 0)) if _native_transmission() else state.stock.belt
	stock_label.text = "ORE DEPOSIT  %d copper\nIN THE LINE  %d copper\nPRESS OUTLET  %d copper plate" % [state.stock.source,
		state.stock.collector + belt_raw + state.stock.input + state.stock.held, state.stock.output]
	power_label.text = "DRIVE RUNNING" if state.get("powered", false) else "DRIVE NEEDS CONNECTIONS"
	save_button.disabled = explanation_open or not save_slot_ready or startup_save_pending or not state.get("actors", {}).get(client, {}).get("ready", false)
	load_button.disabled = explanation_open or not save_slot_ready
	save_button.tooltip_text = "Save worksite  [F5]" if save_slot_ready else "Saving needs a fresh worksite session."
	load_button.tooltip_text = "How to reopen save  [F9]"
	if actor_label != null:
		actor_label.visible = true
		actor_label.text = "CHARACTER READY · BUILD NEARBY" if state.get("actors", {}).get(client, {}).get("ready", false) else "CHARACTER STARTING…"
	if developer_mode_label != null:
		var fast_enabled: bool = state.get("options", {}).get("developer_conveniences", false)
		developer_mode_label.add_theme_color_override("font_color",
			Color("edb95d") if fast_enabled else Color("64777a"))
		developer_mode_label.tooltip_text = "Developer conveniences %s. F3 toggles fast manual harvesting." % (
			"enabled" if fast_enabled else "disabled")
		developer_mode_label.accessibility_name = developer_mode_label.tooltip_text
	retrieve_button.disabled = explanation_open or state.stock.output < 1 or not state.entities.has(selected) or state.entities[selected].kind != "processor"
	remove_button.disabled = explanation_open or not _contains_target(state, selected)
	selection_ring.visible = mode in ["inspect", "flow", "drive"] and state.entities.has(selected)
	if state.entities.has(selected):
		selection_ring.position = _entity_position(state.entities[selected]) + Vector3(0, 0.02, 0)
		inspector.text = _machine_inspection(state.entities[selected], state.stock, state.get("motion", {}).get(selected), _native_transmission())
		inspector.text += "\n" + _inspection_hint()
	elif state.get("foundations", {}).has(selected):
		var surface: Dictionary = state.foundations[selected]
		selection_ring.visible = mode in ["inspect", "flow", "drive"]
		selection_ring.position = _entity_position(surface) + Vector3(0, 0.02, 0)
		var floor_type := "Factory floor" if int(surface.level) % Geometry.HEIGHT_DENOMINATOR == 0 else "Access step · machines need a factory floor"
		inspector.text = "%s\nSquare %s\nTop %.2f m\nRemove to reclaim the carried part." % [floor_type, str(surface.cell), surface.level * Geometry.HEIGHT_STEP]
	elif _native_transmission() and state.get("transmission_parts", {}).has(selected):
		var part: Dictionary = state.transmission_parts[selected]
		var motion: Dictionary = state.get("motion", {}).get(selected, {})
		inspector.text = _transmission_inspection(part, motion)
	elif _native_transmission() and state.get("belt_spans", {}).has(selected):
		inspector.text = _belt_inspection(state.belt_spans[selected], state.get("motion", {}))
	elif _native_transmission() and state.get("fabrication_hub", {}).get("installed", false) \
			and selected == state.fabrication_hub.get("id", ""):
		inspector.text = "Pod workshop\nGrid center %s\nPress E for recipes and stowage." % \
			str(state.fabrication_hub.get("center", []))
	elif _native_transmission() and state.get("placed_components", {}).has(selected):
		var component: Dictionary = state.placed_components[selected]
		inspector.text = "%s\nGrid center %s" % [
			str(component.get("component", "part")).replace("_", " ").capitalize(),
			str(component.get("center", []))]
		if component.get("component", "") == "wooden_workbench":
			inspector.text += "\nPress E for recipes when nearby."
	else:
		inspector.text = "E picks up pointed items or opens machines. Hold E at a placed crank."
	inspector.tooltip_text = inspector.text
	if _object_menu_open() and _contains_target(state, selected):
		var detail_lines := inspector.text.split("\n")
		inspector.text = "\n".join(detail_lines.slice(1, detail_lines.size()))
	else:
		var inspection_lines := inspector.text.split("\n")
		inspector.text = "\n".join(inspection_lines.slice(0, mini(3, inspection_lines.size())))
	_refresh_guided_tools()
	_refresh_manager_log()
	if arrival_assembly_controls != null:
		arrival_assembly_controls.refresh(state, client, selected, _can_use_object_actions())
		if _object_menu_open():
			var selected_placed: bool = state.get("placed_components", {}).has(selected)
			arrival_assembly_controls.reclaim_button.visible = selected_placed
			if selected_placed:
				remove_button.visible = false
		arrival_assembly_scroll.visible = arrival_assembly_controls.visible
		if object_menu_operations != null:
			object_menu_operations.visible = _object_menu_open() and _object_supports_operations(object_menu_target) \
				and arrival_assembly_scroll.visible
	if recovery_actions != null:
		recovery_actions.refresh()
	if loose_material_controls != null:
		loose_material_controls.refresh()
	if arrival_assembly_controls != null and arrival_assembly_controls.inventory_section.is_visible_in_tree():
		# The selected slide's workbed shows the same finite material at its actual
		# work face and outlet. Keep one transfer surface in this object panel.
		if recovery_actions != null:
			recovery_actions.visible = false
		if loose_material_controls != null:
			loose_material_controls.visible = false
	if model is NativeWorldModel:
		ui_refresh_key = _native_ui_key()

func _catalog_open() -> bool:
	return building_hotbar != null and building_hotbar.catalog.visible

func _refresh_manager_log() -> void:
	if manager_log_current == null:
		return
	var complete: bool = state.get("workshop_completed_actors", []).has(client)
	manager_log_completion_entry.visible = complete
	manager_log_projects.visible = complete
	var viewport_height := get_viewport().get_visible_rect().size.y
	var half_height := minf(300.0 if complete else 215.0,
		maxf(180.0, (viewport_height - 32.0) * 0.5))
	manager_log_panel.offset_top = -half_height
	manager_log_panel.offset_bottom = half_height
	manager_log_current.text = "CURRENT FIELD CUE\n" + objective_title + "\n" + goal_text
	if not goal_detail.is_empty():
		manager_log_current.text += "\n\n" + goal_detail

func _notice_workshop_completion(complete: bool) -> void:
	var previously_complete: Variant = workshop_completion_observed
	workshop_completion_observed = complete
	if previously_complete != false or not complete:
		return
	_message("Plate collected. Open the Work log [J].")
	if workshop_completion_audio == null:
		workshop_completion_audio = AudioStreamPlayer.new()
		workshop_completion_audio.name = "WorkshopCompletionChime"
		workshop_completion_audio.volume_db = -13.0
		workshop_completion_audio.stream = ArrivalRevealAudio.workshop_chime()
		add_child(workshop_completion_audio)
	workshop_completion_audio.play()
	workshop_completion_cue_count += 1

func _toggle_manager_log() -> void:
	if manager_log_layer == null or arrival_reveal_active or explanation_open or _catalog_open():
		return
	_release_character_controls()
	manager_log_open = not manager_log_open
	manager_log_layer.visible = manager_log_open
	_refresh_ui()

func _sliding_press_holds_plate(press: Dictionary) -> bool:
	var plate_sites: Array = [press.get("work_center", press.get("center", []))]
	var selected_exit: Array = press.get("selected_exit", [])
	if not selected_exit.is_empty():
		plate_sites.append(selected_exit)
	else:
		for feed: Dictionary in press.get("open_feeds", []):
			plate_sites.append(feed.get("exit", []))
	for drop: Dictionary in state.get("dropped_material", []):
		if int(drop.get("products", 0)) > 0 and plate_sites.has(drop.get("center", [])):
			return true
	return false

func _first_plate_material_cue(carried: Dictionary) -> String:
	var recipes: Dictionary = state.get("component_recipes", {})
	var timber_needed := 0
	var copper_needed := 1 # The blank that becomes the first plate.
	for part: String in ["anvil", "flat_head", "wooden_slide", "hand_crank"]:
		var cost: Dictionary = recipes.get(part, {})
		if cost.is_empty():
			return "Gather timber and copper with the multitool [E]."
		timber_needed += int(cost.get("timber", 0))
		copper_needed += int(cost.get("copper", 0))
	var timber_left := maxi(0, timber_needed - int(carried.get("timber", 0)))
	var copper_left := maxi(0, copper_needed - int(carried.get("raw", 0)))
	if timber_left > 0 and copper_left > 0:
		return "Gather %d timber and %d copper pieces with the multitool [E]." % [timber_left, copper_left]
	if timber_left > 0:
		return "Gather %d timber with the multitool [E] for the first plate." % timber_left
	if copper_left > 0:
		return "Gather %d copper piece%s with the multitool [E]." % [
			copper_left, "" if copper_left == 1 else "s"]
	return "Use Build [B] to craft and fit press parts from carried stock."

func _refresh_guided_tools(snapshot_ready: bool = true) -> void:
	if rotation_button != null:
		rotation_button.visible = _native_transmission() and mode in ["collector", "processor", "wheel"] and not explanation_open
		rotation_button.disabled = not snapshot_ready or not _can_choose_tool()
		rotation_button.text = "Rotate [R]" if mode == "wheel" else "Rotate [R] · %d°" % (building_rotation * 90)
		rotation_button.tooltip_text = "Turn the building by a quarter turn before placing it. Its input, output and horizontal drive axle turn together."
		if mode == "wheel" and transmission_controls != null:
			rotation_button.disabled = rotation_button.disabled or transmission_controls.selected_axis == "y"
			rotation_button.tooltip_text = "Turn the wheel axle between X and Z."
	if foundation_level_controls != null:
		foundation_level_controls.visible = _native_transmission() and mode in ["foundation", "wheel"] and not explanation_open and snapshot_ready
		foundation_area_toggle.visible = foundation_level_controls.visible and mode == "foundation"
		foundation_steps_toggle.visible = foundation_area_toggle.visible
		foundation_steps_toggle.text = "Access steps  [Z]"
		foundation_area_toggle.text = "Area: two corners  [V]"
		foundation_level_label.text = _construction_height_text()
		(foundation_level_controls.get_child(0) as Button).text = "−  [PgDn]"
		(foundation_level_controls.get_child(2) as Button).text = "+  [PgUp]"
		wheel_size_controls.visible = foundation_level_controls.visible and mode == "wheel"
		(wheel_size_controls.get_child(0) as Button).text = "−  [Shift+PgDn]"
		(wheel_size_controls.get_child(2) as Button).text = "+  [Shift+PgUp]"
	footer_snapshot_ready = snapshot_ready
	_queue_footer_fit()
	if building_hotbar != null:
		building_hotbar.refresh(snapshot_ready)
	# This is a view of confirmed facts, not persistent progression or admission.
	var kinds: Dictionary = {}
	for entity in state.get("entities", {}).values():
		kinds[String(entity.kind)] = true
	var offered := {"collector": true}
	if kinds.has("collector"):
		offered.belt = true
	if kinds.has("belt") or (_native_transmission() and not state.get("belt_spans", {}).is_empty()):
		offered.processor = true
	if kinds.has("processor"):
		offered.wheel = true
	if (kinds.has("collector") and kinds.has("belt")) or (kinds.has("belt") and kinds.has("processor")):
		offered.flow = true
	if kinds.has("wheel") and kinds.size() > 1:
		offered.drive = true
	var arrival := _native_transmission() and state.has("hand_sources")
	var step := {"tool": "inspect", "text": ""} if arrival else _guided_step(kinds)
	if state.get("options", {}).get("foundations", false):
		offered.foundation = true
	for tool in tool_buttons:
		if building_hotbar.catalog_buttons.has(tool):
			continue
		var button: Button = tool_buttons[tool]
		# Keyboard selection stays visible even when it precedes the suggestion.
		button.visible = (NAMES.has(tool) or building_hotbar.catalog_buttons.has(tool) or offered.has(tool) or mode == tool) \
			and not (arrival and tool in ["collector", "processor"])
		if tool == "foundation" and not state.get("options", {}).get("foundations", false):
			button.visible = false
		if tool in ["gear", "gearbox", "vertical_gearbox", "chain_drive"] and not _native_transmission():
			button.visible = false
		for color_name in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			if tool == step.tool:
				button.add_theme_color_override(color_name, Color("edcc8d"))
			else:
				button.remove_theme_color_override(color_name)
	var inventory := int(state.get("inventories", {}).get(client, 0))
	var workshop_complete: bool = arrival and state.get("workshop_completed_actors", []).has(client)
	objective_title = ("FIRST WORKSHOP  /  COMPLETE" if workshop_complete else "FIRST WORKSHOP  /  01") \
		if arrival else "FIRST SHIFT  /  01"
	if arrival:
		var carried: Dictionary = state.get("cargo", {}).get(client, {})
		var next_work := _first_plate_material_cue(carried)
		var press_ready := false
		var sliding_press_ready := false
		var sliding_plate_waiting := false
		var ready_slide_has_crank := false
		var sliding_feed_blocked := false
		var collector_ready := false
		for press: Dictionary in state.get("guided_press_assemblies", []):
			press_ready = press_ready or press.get("status") == "ready"
		for press: Dictionary in state.get("sliding_press_assemblies", []):
			sliding_press_ready = sliding_press_ready or press.get("status") == "ready"
			if press.get("status") == "ready":
				sliding_plate_waiting = sliding_plate_waiting or _sliding_press_holds_plate(press)
			sliding_feed_blocked = sliding_feed_blocked or press.get("status") == "blocked_feed"
			press_ready = press_ready or press.get("status") == "ready"
			if press.get("status") == "ready":
				var slide_id: String = str(press.get("parts", {}).get("slide", ""))
				for crank: Dictionary in state.get("crank_items", {}).values():
					ready_slide_has_crank = ready_slide_has_crank or (
						not slide_id.is_empty() and crank.get("attached_to", "") == slide_id)
		for collector: Dictionary in state.get("collector_assemblies", []):
			collector_ready = collector_ready or collector.get("status") == "ready"
		if snapshot_ready:
			_notice_workshop_completion(workshop_complete)
		if workshop_complete:
			var build_stage: String = building_hotbar._suggested_recipe_category(self) \
				if building_hotbar != null else "power"
			match build_stage:
				"logistics": next_work = "Open Build [B] for Logistics, then route the collector output by belt."
				"machine": next_work = "Open Build [B] for collector parts at the ore face."
				_: next_work = "Open Build [B] for Power. Craft a Shaft and cogwheels at a bench."
		elif sliding_plate_waiting:
			next_work = "Plate on the workbed. Aim at the offcuts and press [E]."
		elif sliding_press_ready and ready_slide_has_crank:
			next_work = "Open the press [E]. Move copper to the workbed, then point at the crank and hold E."
		elif sliding_press_ready:
			next_work = "Place your carried crank at a slide input [B], then open the press [E]." \
				if int(carried.get("components", {}).get("hand_crank", 0)) > 0 else \
				"Craft a hand crank [B], place it at a slide input, then open the press [E]."
		elif state.get("first_plate_unlock", false) and sliding_feed_blocked:
			next_work = "Clear an X-side feed path [F], then open the press [E]."
		elif press_ready:
			next_work = "Feed copper at the press [E], then hold E on its placed crank in the world."
		elif state.get("first_plate_unlock", false) and not state.get("placed_components", {}).is_empty():
			next_work = "Inspect placed parts [E] and use Build [B] for what the press still needs."
		elif state.get("first_plate_unlock", false) and (
				not carried.get("components", {}).is_empty() or
				int(carried.get("timber", 0)) >= 3 or int(carried.get("raw", 0)) >= 4):
			next_work = "Use Build [B] to craft and fit press parts from carried stock."
		elif collector_ready and int(state.get("line_belt_raw", 0)) > 0:
			next_work = "Blank on belt. Inspect its outlet [E] or recover it."
		elif collector_ready:
			next_work = "Collector ready. Cut ore or connect a material route."
		elif not state.get("placed_components", {}).is_empty():
			next_work = "Inspect parts [E] or build [B]."
		elif not carried.get("components", {}).is_empty():
			next_work = "Place a carried part [B]."
		elif int(carried.get("timber", 0)) >= 3:
			next_work = "Craft a part in Build [B]."
		goal_text = (next_work if workshop_complete else "FORM A PLATE · KEEP IT\n" + next_work) \
			if snapshot_ready else "Connect to the worksite."
	else:
		goal_text = "Make 4 plates  ·  %d / 4\n%s" % [inventory, step.text] if snapshot_ready else "Connect to the worksite."
	actor_label.visible = true
	controls_label.text = "WASD move · E interact · B build · F remove · C link · J log · H help" if arrival \
		else "B catalog · 1–8 build · E open · F remove · C link · J log · H help"
	_refresh_engineering(snapshot_ready)
	if explanation_open:
		help_title.text = objective_title
		help_body.text = _help_goal_text()
	var target_selected: bool = _contains_target(state, selected)
	inspector_title.visible = object_menu == null and (target_selected or not snapshot_ready or not _can_choose_tool())
	inspector.visible = target_selected if object_menu != null else target_selected \
		or not snapshot_ready or not _can_choose_tool()
	retrieve_button.visible = state.get("entities", {}).get(selected, {}).get("kind") == "processor"
	remove_button.visible = target_selected
	inspection_actions.visible = target_selected
	for divider in inspector.get_parent().get_children():
		if divider is HSeparator:
			divider.visible = target_selected

func _placement_ready() -> bool:
	return _can_control_character()

func _preview_pointer_clear() -> bool:
	# This query does not consume input or move the pointer. The live preview
	# follows the current camera ray, including when the view moves under it.
	if component_nudge_active and mode == "component":
		return is_inside_tree()
	return is_inside_tree() and get_viewport().get_visible_rect().has_point(_pointed_screen_position()) \
		and (get_viewport().gui_get_hovered_control() == null or _pointer_over_placement_options())

func _pointer_over_placement_options() -> bool:
	if placement_options_panel == null or not placement_options_panel.visible or not is_inside_tree():
		return false
	var hovered := get_viewport().gui_get_hovered_control()
	while hovered != null:
		if hovered == placement_options_panel:
			return true
		hovered = hovered.get_parent() as Control
	return false

func _machine_preview_cell() -> Vector2i:
	return placement_cell_cache if _pointer_over_placement_options() else _screen_cell(get_viewport().get_mouse_position())

func _preview_axis() -> int:
	if not _native_transmission() or transmission_controls == null:
		return 0
	var axis: int = ["x", "y", "z"].find(transmission_controls.selected_axis)
	if mode in ["collector", "processor"] and axis != 1 and building_rotation % 2 == 1:
		return 2 - axis
	return axis

func _rotate_building() -> void:
	if not _native_transmission() or not _can_choose_tool() or mode not in ["collector", "processor", "wheel"] or explanation_open:
		return
	if mode == "wheel":
		if transmission_controls == null or transmission_controls.selected_axis not in ["x", "z"]:
			return
		transmission_controls.selected_axis = "z" if transmission_controls.selected_axis == "x" else "x"
		transmission_controls.refresh()
	else:
		building_rotation = (building_rotation + 1) % 4
	_update_cursor()
	_refresh_ui()

func _cycle_placement_axis() -> void:
	if transmission_controls == null or not _can_choose_tool() or mode not in ["wheel", "gear", "drive", "vertical_gearbox", "chain_drive"]:
		return
	var axes := ["x", "y", "z"]
	var next_axis: int = (axes.find(transmission_controls.selected_axis) + 1) % axes.size()
	if mode in ["wheel", "vertical_gearbox"] and next_axis == 1:
		next_axis = 2
	transmission_controls._axis_selected(next_axis)
	transmission_controls.refresh()
	_update_cursor()
	_refresh_ui()

func _refresh_placement_options() -> void:
	if placement_options_panel == null:
		return
	var placing_machine := machine_preview != null and machine_preview.visible
	var placing_component := mode == "component" and component_preview != null and component_preview.visible
	var placing_pod := mode == "pod_workshop" and hover != null and hover.visible
	var placing_transmission: bool = _native_transmission() and transmission_controls != null \
		and transmission_controls.active_tool in ["gear", "place_shaft", "belt_span", "gearbox", "vertical_gearbox", "chain_drive"]
	var shown: bool = _native_transmission() and not explanation_open and not _catalog_open() and _can_choose_tool() \
		and (placing_machine or placing_component or placing_pod or placing_transmission)
	placement_options_panel.visible = shown
	if not shown:
		return
	var tool: String = {"place_shaft": "drive", "belt_span": "belt"}.get(transmission_controls.active_tool, mode) \
		if placing_transmission else mode
	placement_options_title.text = "CONNECT BELT" if tool == "belt" else "PLACE %s" % {
		"gearbox": "HORIZONTAL GEARBOX", "vertical_gearbox": "VERTICAL GEARBOX",
		"chain_drive": "ENCASED CHAIN DRIVE",
		"component": arrival_assembly_controls.selected_name().replace("_", " ").to_upper() if arrival_assembly_controls != null else "COMPONENT"}.get(tool, NAMES.get(tool, tool).to_upper())
	placement_options_hint.text = {
		"foundation": "Left click to build · choose height or area below · Esc cancels",
		"wheel": "Left click to build · R turns the axle · choose size or height below",
		"gear": "Left click to build · choose axle, height or size below",
		"drive": "Left click to build · choose axle or height below",
		"gearbox": "Left click to build · adjust height below",
		"vertical_gearbox": "Left click to build · choose axle or height below",
		"chain_drive": "Left click to build · choose axle and chain link direction below",
		"belt": "Hover the second shaft to preview · Click to connect · Esc cancels"
			if transmission_controls != null and not transmission_controls._belt_start.is_empty()
			else "Click the first shaft · Esc cancels",
		"component": _component_placement_hint(),
		"pod_workshop": "Left click to reinstall on the full tile · Esc cancels",
	}.get(tool, "Left click to build · R rotates · Esc cancels")
	placement_options_axis.visible = tool in ["wheel", "gear", "drive", "vertical_gearbox", "chain_drive"]
	placement_options_axis.text = "Axle: %s  [X]" % (transmission_controls.selected_axis.to_upper()
		if transmission_controls != null else "X")
	_fit_placement_options()

func _fit_placement_options() -> void:
	var parent := placement_options_panel.get_parent() as Control
	var height: float = placement_options_panel.get_combined_minimum_size().y
	placement_options_panel.size = Vector2(maxf(302.0, placement_options_panel.get_combined_minimum_size().x), height)
	var hotbar_height: float = building_hotbar.size.y if building_hotbar != null else 0.0
	var footer_height: float = status_footer.size.y if status_footer != null and status_footer.visible else 0.0
	placement_options_panel.position = Vector2(maxf(18.0, parent.size.x - placement_options_panel.size.x - 18.0),
		18.0 if mode == "component" else maxf(18.0,
			parent.size.y - hotbar_height - footer_height - placement_options_panel.size.y - 48.0))

func _refresh_machine_preview() -> void:
	if machine_preview != null:
		machine_preview.visible = false
	if explanation_open or not _placement_ready() or not _preview_pointer_clear():
		return
	if _native_transmission() and transmission_controls != null \
			and transmission_controls.active_tool == "belt_span":
		_refresh_belt_preview()
		return
	if _native_transmission() and transmission_controls != null \
			and transmission_controls.active_tool in ["gear", "place_shaft"]:
		_refresh_transmission_preview()
		return
	if not NAMES.has(mode) or int(_display_parts().get(mode, 0)) < 1:
		return
	if transmission_controls != null and not transmission_controls.active_tool.is_empty():
		return
	var cell := _machine_preview_cell()
	if not _pointer_over_placement_options():
		placement_cell_cache = cell
	if not _build_cell_allowed(cell) or not _machine_floor_aligned(cell) or (mode != "foundation" and not _entity_at_cell(cell).is_empty()):
		return
	var area_size := Vector2i.ONE
	var area_origin := cell
	if mode == "foundation" and foundation_area_mode and foundation_area_started:
		area_size = Vector2i(absi(cell.x - foundation_area_start.x) + 1, absi(cell.y - foundation_area_start.y) + 1)
		area_origin = Vector2i(mini(cell.x, foundation_area_start.x), mini(cell.y, foundation_area_start.y))
		if area_size.x > 256 or area_size.y > 256 or area_size.x * area_size.y > 256:
			return
	var axis := _preview_axis()
	if axis < 0:
		return
	var facing := building_rotation if mode in ["collector", "processor"] else 0
	var level := _construction_level(cell)
	if mode == "collector" and _native_transmission() and not Geometry.collector_intake_boxes(
		{"kind": "collector", "cell": [cell.x, cell.y], "level": level}).get("accepted", false):
		return
	var key := "%s:%d:%s:%d:%d:%s" % [mode, axis, str(_native_transmission()), wheel_tiles if mode == "wheel" else 0, facing,
		str([cell.x, cell.y, level]) if mode == "collector" else ""]
	var packaged: bool = mode == "foundation" or _native_transmission() and axis == 0 and facing == 0 \
		and (mode != "wheel" or wheel_tiles == 3) \
		and (mode != "collector" or cell == Vector2i(0, 1) and level == 0)
	var pooled: Node3D = packed_preview_nodes.get(mode) if packaged else null
	_choose_machine_preview(pooled)
	if pooled != null:
		machine_preview_key = key
	machine_preview.basis = Basis.IDENTITY
	machine_preview.position = _cell_position([cell.x, cell.y]) + Vector3.UP * level * Geometry.HEIGHT_STEP
	if key != machine_preview_key:
		for child in machine_preview.get_children():
			child.free()
		# The placed wheel's observed animation target must not be replaced by
		# the visual-only assembly. Preview construction changes no projection.
		var placed_rotor := wheel_rotor
		if mode == "foundation":
			_assemble_foundation(machine_preview)
		else:
			if packaged and packed_preview_templates.has(mode):
				var packed: PackedScene = packed_preview_templates.get(mode)
				var template := packed.instantiate() as Node3D
				machine_preview.set_meta("material_rotated", template.get_meta("material_rotated", false))
				for part in template.get_children():
					part.owner = null
					template.remove_child(part)
					machine_preview.add_child(part)
				template.free()
			else:
				var variant := _packed_machine_preview_variant(mode, axis, wheel_tiles, facing, cell, level)
				if preview_variant_pending:
					wheel_rotor = placed_rotor
					return
				if variant != null:
					machine_preview.set_meta("material_rotated", variant.get_meta("material_rotated", false))
					for part in variant.get_children():
						_clear_preview_owners(part)
						variant.remove_child(part)
						machine_preview.add_child(part)
					variant.free()
				else:
					_assemble_machine(machine_preview, {"kind": mode, "axis": axis, "tiles": wheel_tiles,
						"rotation": facing, "cell": [cell.x, cell.y], "level": level}, mode == "belt" and axis == 0)
					if mode in ["collector", "processor"]:
						_preview_port(machine_preview, facing, mode == "collector")
		wheel_rotor = placed_rotor
		_style_machine_preview(machine_preview)
		machine_preview_key = key
	machine_preview.scale = Vector3.ONE
	if mode == "foundation":
		machine_preview.scale = Vector3(area_size.x, 1, area_size.y)
		machine_preview.position.x = (area_origin.x + (area_size.x - 1) / 2.0) * PITCH
		machine_preview.position.z = (area_origin.y + (area_size.y - 1) / 2.0) * PITCH
	machine_preview.visible = true

func _refresh_transmission_preview() -> void:
	var context: Dictionary = transmission_controls._context()
	if context.is_empty() or not context.usable:
		return
	var gear: bool = transmission_controls.active_tool == "gear"
	var size: int = transmission_controls.gear_teeth if gear else transmission_controls.shaft_half_span
	if transmission_controls._count(context, "gear" if gear else "shaft", size if gear else 0, 0 if gear else size) < 1:
		return
	var axis := _preview_axis()
	if axis < 0:
		return
	var center: Array
	if _pointer_over_placement_options() and not transmission_preview_point.is_empty():
		center = transmission_preview_point.duplicate()
		center[1] = transmission_controls.snapped_height if transmission_controls.auto_height else transmission_controls.gear_height
	else:
		center = _transmission_center(_pointed_screen_position())
		transmission_preview_point = center.duplicate()
	if not Geometry._mechanical_point(center):
		return
	_choose_machine_preview()
	machine_preview.position = Geometry._mechanical_center(center)
	var key := "transmission:%s:%d:%d" % [transmission_controls.active_tool, axis, size]
	if key != machine_preview_key:
		for child in machine_preview.get_children():
			child.free()
		var assets = load("res://opening/native_transmission_assets.gd")
		machine_preview.basis = load("res://opening/native_transmission_presenter.gd").axis_basis(axis)
		if gear:
			var mesh := MeshInstance3D.new()
			mesh.name = "Cogwheel"
			mesh.mesh = assets.complete_gear_mesh(PITCH / 2.0, size, Color("687a7b"), PITCH)
			machine_preview.add_child(mesh)
		else:
			assets.shaft(machine_preview, size * Geometry.HEIGHT_STEP * 2.0, Color("687a7b"))
		_style_machine_preview(machine_preview)
		machine_preview_key = key
	machine_preview.scale = Vector3.ONE
	machine_preview.visible = true

func _refresh_belt_preview() -> void:
	# A translucent loop follows two confirmed shaft identities under the
	# pointer. Native Host still decides reach, clearance and kit spending.
	if _pointer_over_placement_options() or transmission_presenter == null:
		return
	var context: Dictionary = transmission_controls._context()
	var selected: Dictionary = transmission_controls._belt_start
	if context.is_empty() or not context.usable or selected.is_empty() \
			or selected.get("pending", false) or not selected.get("placement_request", "").is_empty() \
			or context.world != selected.get("world") or context.actor != selected.get("actor"):
		return
	var parts: Variant = context.snapshot.get("transmission_parts")
	if not parts is Dictionary:
		return
	var first: Variant = parts.get(selected.get("id", ""), {})
	if not first is Dictionary or first.get("generation") != selected.get("generation"):
		return
	var hit := _screen_pick(_pointed_screen_position())
	if hit.is_empty():
		return
	var candidate := _picked_target_id(hit)
	if candidate.is_empty() or candidate == selected.id:
		return
	var last: Variant = parts.get(candidate, {})
	var frame: Dictionary = transmission_presenter.belt_visual_frame(first, last)
	if frame.is_empty():
		return
	_choose_machine_preview()
	var key := "belt:%s:%s:%s:%s" % [selected.id, candidate, first.generation, last.generation]
	if key != machine_preview_key:
		for child in machine_preview.get_children():
			child.free()
		var assets = load("res://opening/native_transmission_assets.gd")
		var loop: MeshInstance3D = assets.belt_loop(machine_preview, frame.distance, 0)
		if loop == null:
			return
		loop.basis = frame.loop_basis
		_style_machine_preview(machine_preview)
		if belt_preview_material == null:
			belt_preview_material = machine_preview_material.duplicate()
			belt_preview_material.albedo_color = Color(1.0, 0.56, 0.16, 0.42)
			belt_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_style_machine_preview(machine_preview, belt_preview_material)
		machine_preview_key = key
	machine_preview.position = frame.position
	machine_preview.basis = Basis.IDENTITY
	machine_preview.scale = Vector3.ONE
	machine_preview.set_meta("belt_preview_from", selected.id)
	machine_preview.set_meta("belt_preview_to", candidate)
	machine_preview.visible = true

func _preview_port(parent: Node3D, facing: int, output: bool) -> void:
	var forward := Vector3.RIGHT.rotated(Vector3.UP, -float(facing) * PI / 2.0)
	var side := forward if output else -forward
	var at := side * 0.9 + Vector3.UP * 0.6
	var direction := forward
	var across := Vector3(-direction.z, 0, direction.x)
	var tip := at + direction * 0.23
	_route_segment(parent, "PortArrow", at - direction * 0.23, tip, 0.055, Color("edcc8d"))
	_route_segment(parent, "PortArrowLeft", tip - direction * 0.15 + across * 0.12, tip, 0.055, Color("edcc8d"))
	_route_segment(parent, "PortArrowRight", tip - direction * 0.15 - across * 0.12, tip, 0.055, Color("edcc8d"))
	var label := Label3D.new()
	label.name = "MaterialPortLabel"
	label.text = "OUT" if output else "IN"
	label.position = side * 0.9 + Vector3.UP * 0.95
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 32
	label.pixel_size = 0.01
	label.outline_size = 6
	label.set_meta("port_side", side)
	parent.add_child(label)

func _style_machine_preview(node: Node, material: Material = null) -> void:
	# Per-instance overrides leave shared placed materials and meshes intact.
	# Neutral amber is a form/footprint preview, never an admission verdict.
	if machine_preview_material == null:
		machine_preview_material = StandardMaterial3D.new()
		machine_preview_material.albedo_color = Color(0.88, 0.75, 0.49, 0.32)
		machine_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		machine_preview_material.roughness = 0.75
		machine_preview_material.metallic = 0.0
	if node is MeshInstance3D:
		node.material_override = material if material != null else machine_preview_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_style_machine_preview(child, material)

func _guided_span_path(routes: Array, collector: Vector3i, processor: Vector3i, powered: bool) -> bool:
	# A loose item leaving a span can be picked up on any tile of another span.
	# This is advisory over confirmed projection facts, not construction authority.
	var queue: Array[int] = []
	var visited := {}
	for index in range(routes.size()):
		var route: Dictionary = routes[index]
		var entry := 0 if collector == route.before else (1 if collector == route.after else -1)
		if entry < 0 or (powered and (not route.rotating or (entry == 0) != route.forward)):
			continue
		queue.append(index)
		visited[index] = true
	while not queue.is_empty():
		var current: int = queue.pop_front()
		var route: Dictionary = routes[current]
		var exits: Array = [route.after if route.forward else route.before] if powered else [route.before, route.after]
		for outlet: Vector3i in exits:
			if outlet == processor:
				return true
			for index in range(routes.size()):
				var next: Dictionary = routes[index]
				if visited.has(index) or (powered and not next.rotating) or not next.tiles.has(outlet):
					continue
				visited[index] = true
				queue.append(index)
	return false

func _guided_span_routes() -> Dictionary:
	var result := {"physical": false, "powered": false, "cargo": false}
	var parts: Variant = state.get("transmission_parts", {})
	var spans: Variant = state.get("belt_spans", {})
	var entities: Variant = state.get("entities", {})
	var motion: Variant = state.get("motion", {})
	if not parts is Dictionary or not spans is Dictionary or not entities is Dictionary or not motion is Dictionary:
		return result
	var collector: Variant = null
	var processor: Variant = null
	for entity: Variant in entities.values():
		if not entity is Dictionary or not entity.get("center") is Array or entity.center.size() != 3:
			continue
		if entity.get("kind") == "collector":
			collector = Vector3i(entity.center[0], entity.center[1], entity.center[2])
		elif entity.get("kind") == "processor":
			processor = Vector3i(entity.center[0], entity.center[1], entity.center[2])
	var routes: Array = []
	for span: Variant in spans.values():
		if not span is Dictionary or not span.get("slots") is Array:
			continue
		for item: Variant in span.slots:
			if item is Dictionary:
				result.cargo = true
		var first: Variant = parts.get(span.get("from", ""))
		var last: Variant = parts.get(span.get("to", ""))
		if not first is Dictionary or not last is Dictionary or first.get("axis") not in [0, 2] or first.get("axis") != last.get("axis") or not first.get("center") is Array or not last.get("center") is Array or first.center.size() != 3 or last.center.size() != 3:
			continue
		var start := Vector3i(first.center[0], first.center[1], first.center[2])
		var finish := Vector3i(last.center[0], last.center[1], last.center[2])
		var delta := finish - start
		var steps := maxi(absi(delta.x), maxi(absi(delta.y), absi(delta.z))) / 4
		if steps < 1 or steps > 19 or (delta.x == 0 and delta.z == 0) or delta[first.axis] != 0:
			continue
		var valid_path := true
		for coordinate in range(3):
			if start[coordinate] % 4 != 0 or (delta[coordinate] != 0 and absi(delta[coordinate]) != steps * 4):
				valid_path = false
		if not valid_path:
			continue
		var step := delta / steps
		var tiles: Array = []
		for index in range(steps + 1):
			tiles.append(start + step * index)
		var shaft_motion: Variant = motion.get(span.get("from", ""), {})
		var rotating: bool = shaft_motion is Dictionary and shaft_motion.get("state") == "rotating" and typeof(shaft_motion.get("numerator")) == TYPE_INT and shaft_motion.numerator != 0
		var positive: bool = rotating and ((first.axis == 0 and shaft_motion.numerator > 0) or (first.axis == 2 and shaft_motion.numerator < 0))
		var along := delta.z if first.axis == 0 else delta.x
		routes.append({"before": start - step, "after": finish + step, "tiles": tiles,
			"rotating": rotating, "forward": positive == (along > 0)})
	if collector is Vector3i and processor is Vector3i:
		result.physical = _guided_span_path(routes, collector, processor, false)
		result.powered = _guided_span_path(routes, collector, processor, true)
		# The native assessment also accounts for collector-side competition;
		# a geometric path alone can be starved by an earlier fast branch.
		var reports: Variant = state.get("opening_engineering", {})
		var report: Variant = reports.get(client, {}) if reports is Dictionary else {}
		if report is Dictionary and report.get("schema") == 1 and report.get("format") == "factory-opening-engineering" \
				and report.get("actor") == client and report.get("known_actor") == true and typeof(report.get("belt_forward")) == TYPE_BOOL:
			result.powered = result.physical and report.belt_forward
	return result

func _guided_step(kinds: Dictionary) -> Dictionary:
	if int(state.get("inventories", {}).get(client, 0)) >= 4:
		return {"text": "Four plates collected. Keep building or try another layout.", "tool": "inspect"}
	if int(state.get("stock", {}).get("output", 0)) > 0:
		return {"text": "Plate ready. Point at the press and open [E], then collect [R].", "tool": "inspect"}
	if not kinds.has("collector"):
		if _native_transmission():
			return {"text": FIRST_COLLECTOR_HINT if mode == "inspect" else "Place a collector at the exposed ore deposit.", "tool": "collector"}
		return {"text": "Place a collector on the brass strip near you.", "tool": "collector"}
	var spans: Dictionary = state.get("belt_spans", {}) if _native_transmission() else {}
	if not kinds.has("belt") and spans.is_empty():
		return {"text": "Place two parallel shafts, then connect them with a belt.", "tool": "drive"} if _native_transmission() else {"text": "Add a belt beside the collector.", "tool": "belt"}
	if not kinds.has("processor"):
		return {"text": "Add a press at the belt outlet.", "tool": "processor"}
	var material_pairs: Dictionary = {}
	for pair in state.get("links", []):
		var entities: Dictionary = state.get("entities", {})
		if entities.has(pair[0]) and entities.has(pair[1]):
			material_pairs["%s:%s" % [entities[pair[0]].kind, entities[pair[1]].kind]] = true
	var span_route := _guided_span_routes() if _native_transmission() else {"physical": false, "powered": false, "cargo": false}
	var legacy_route := material_pairs.has("collector:belt") and material_pairs.has("belt:processor")
	if not span_route.physical and not legacy_route:
		if not spans.is_empty() and not kinds.has("belt"):
			return {"text": "Connect the collector and press with horizontal or inclined belts.", "tool": "drive"}
		return {"text": "Connect the material path. Help [H] shows an example.", "tool": "flow"}
	if not kinds.has("wheel"):
		return {"text": "Place a waterwheel in the stream.", "tool": "wheel"}
	if _native_transmission():
		var motion: Dictionary = state.get("motion", {})
		for id in state.get("entities", {}):
			var part: Dictionary = state.entities[id]
			if part.get("kind", "") in ["collector", "belt", "processor"] and motion.get(id, {}).get("state", "") != "rotating":
				return {"text": "Use cogs and shafts to bring rotation to each machine. The belt shaft crosses its direction of travel.", "tool": "drive"}
			if part.get("kind", "") == "belt" and motion.get(id, {}).get("state", "") == "rotating" and int(motion.get(id, {}).get("numerator", 0)) > 0:
				return {"text": "The belt is carrying copper away from the press. Change the cog route to reverse its rotation.", "tool": "drive"}
		if span_route.physical and not span_route.powered and not legacy_route:
			return {"text": "Power the belt shafts, check their direction toward the press, and check branches for diverted copper.", "tool": "drive"}
	elif not state.get("powered", false):
		return {"text": "Bring power to the line. Help [H] shows the current setup.", "tool": "drive"}
	var stock: Dictionary = state.get("stock", {})
	if _native_transmission() and not span_route.cargo and state.get("dropped_material", []).any(func(drop: Variant): return drop is Dictionary and int(drop.get("raw", 0)) > 0) and int(stock.get("source", 0)) + int(stock.get("collector", 0)) + int(stock.get("belt", 0)) + int(stock.get("input", 0)) + int(stock.get("held", 0)) == 0:
		return {"text": "Pick up loose copper nearby, then insert it into the press.", "tool": "inspect"}
	if not span_route.cargo and int(stock.get("source", 0)) + int(stock.get("collector", 0)) + int(stock.get("belt", 0)) + int(stock.get("input", 0)) + int(stock.get("held", 0)) == 0:
		if _native_transmission():
			var cargo: Dictionary = state.get("cargo", {}).get(client, {})
			if not cargo.get("work_lots", []).is_empty():
				return {"text": "Point at the press and open [E] to insert a carried copper workpiece.", "tool": "inspect"}
			if int(cargo.get("raw", 0)) > 0:
				return {"text": "Point at the press and open [E] to insert carried copper.", "tool": "inspect"}
		return {"text": "No copper remains here. Open Build to try another layout.", "tool": "inspect"}
	return {"text": "Follow the material toward the press. Point at a machine and open it [E].", "tool": "inspect"}

func _inspection_hint() -> String:
	# Describe confirmed projection facts only. This is advice, never admission
	# or a second power solver; the authority still decides every command.
	var kind: String = state.entities[selected].kind
	var rotating: bool = state.get("powered", false)
	if _native_transmission():
		rotating = state.get("motion", {}).get(selected, {}).get("state", "") == "rotating"
	if kind == "processor" and state.stock.output > 0:
		return "Outlet full; copper plate ready.\n[R] collect to make room."
	if kind == "processor" and state.stock.held > 0 and rotating:
		if state.remaining == 0:
			return "Work done; copper retained.\nNext drive tick releases a copper plate."
		return "Working: %d ticks remaining.\nHeld copper stays in the press." % state.remaining
	if kind in ["belt", "processor"] and not _has_material_connection(true):
		return "No material inlet linked.\n" + ("[C]" if _native_transmission() else "[F]") + " link " + ("Collector → Belt." if kind == "belt" else "Belt → Press.")
	if kind in ["collector", "belt"] and not _has_material_connection(false):
		return "No material outlet linked.\n" + ("[C]" if _native_transmission() else "[F]") + " link " + ("Collector → Belt." if kind == "collector" else "Belt → Press.")
	if not rotating:
		if _native_transmission():
			if kind == "wheel":
				return "Wheel is not rotating. Check its axle and the stream."
			return "Bring rotation to the line.\n[G] shafts; mesh cogwheels."
		return "Drive needs connections.\n[G] link wheel + all machines."
	if kind == "processor":
		if state.stock.input > 0:
			return "Copper ready to press.\nNext drive tick starts work."
		return "Waiting for copper.\nInspect the Belt upstream."
	if kind == "collector":
		if state.stock.source == 0:
			return "Ore deposit depleted.\nNo copper remains to collect."
		if state.stock.collector > 0:
			return "Collector outlet occupied.\nInspect the Belt downstream."
		return "Cutting copper from the finite deposit.\nBelt takes the next piece."
	if kind == "belt":
		return "Belt carrying copper.\nInspect the Press downstream." if state.stock.belt > 0 else "Waiting for copper.\nInspect the Collector upstream."
	return "Wheel rotates in the stream.\nConnected parts receive its motion."

func _has_material_connection(incoming: bool) -> bool:
	for pair in state.links:
		if pair[1 if incoming else 0] == selected:
			return true
	return false

func _refresh_machine_captions() -> void:
	if not _native_transmission() or machine_root == null:
		return
	for anchor in machine_root.get_children():
		var caption := anchor.get_node_or_null("MachineCaption") as Label3D
		if caption == null:
			continue
		var entity_id: String = anchor.get_meta("machine_entity", "")
		caption.visible = not explanation_open and (entity_id == selected \
			or entity_id == pending_link)

func _update_cursor() -> void:
	_refresh_machine_preview()
	_refresh_component_preview()
	_refresh_machine_captions()
	if _native_transmission() and transmission_controls != null and not transmission_controls.active_tool.is_empty():
		hover.visible = false
		if transmission_controls.active_tool in ["gearbox", "vertical_gearbox", "chain_drive"] and not explanation_open and _can_control_character():
			_set_transmission_hover(_transmission_center(get_viewport().get_mouse_position()))
		_refresh_placement_options()
		return
	hover.basis = Basis.IDENTITY
	hover.scale = Vector3.ONE
	if mode == "pod_workshop" and _native_transmission():
		var hub: Dictionary = state.get("fabrication_hub", {})
		hover.visible = hub.get("holder") == client and _preview_pointer_clear() \
			and _build_cell_allowed(hover_cell) and not explanation_open
		if hover.visible:
			hover.position = _cell_position([hover_cell.x, hover_cell.y]) + Vector3.UP * \
				(0.03 + _construction_level(hover_cell) * Geometry.HEIGHT_STEP)
		_refresh_placement_options()
		return
	if mode == "component" and _native_transmission():
		hover.visible = false
		_refresh_placement_options()
		return
	hover.visible = NAMES.has(mode) and _build_cell_allowed(hover_cell) and _machine_floor_aligned(hover_cell) \
		and (mode == "foundation" or _entity_at_cell(hover_cell).is_empty()) and not explanation_open
	if hover.visible:
		hover.position = _cell_position([hover_cell.x, hover_cell.y]) + Vector3(0, 0.03 + _construction_level(hover_cell) * Geometry.HEIGHT_STEP, 0)
	_refresh_placement_options()

func _set_transmission_hover(center: Array) -> void:
	if center.size() != 3 or absi(center[0]) > Geometry.GRID_COORDINATE_LIMIT or absi(center[1]) > Geometry.GRID_COORDINATE_LIMIT or absi(center[2]) > Geometry.GRID_COORDINATE_LIMIT:
		return
	hover.visible = true
	hover.position = Vector3(center[0] * Geometry.HEIGHT_STEP,
		0.03 + center[1] * Geometry.HEIGHT_STEP, center[2] * Geometry.HEIGHT_STEP)
	hover.basis = Basis.IDENTITY

func _message(words: String, refused: bool = false) -> void:
	status_label.text = words
	status_refused = refused
	status_label.modulate = Color("e0a880") if refused else Color("d6dfd6")
	_queue_footer_fit()

func _queue_footer_fit() -> void:
	if status_footer == null or footer_fit_pending:
		return
	footer_fit_pending = true
	_fit_guided_footer.call_deferred()

func _footer_above_view() -> bool:
	# A nearby third-person worker fills the lower centre of the view. Use the
	# free lane above the worker; Help keeps its own upper reading space.
	return distance > 1.0 and distance <= 6.0 and not explanation_open

func _fit_guided_footer() -> void:
	footer_fit_pending = false
	# Wrapped text settles after its container width. Fit again at that
	# boundary, rather than retaining an early oversized minimum height.
	var columns_to_fit := [] if object_menu != null else [inspector.get_parent() if inspector != null else null]
	for column in columns_to_fit:
		if column != null:
			var panel: Control = column.get_parent()
			if column == inspector.get_parent():
				var content_visible := false
				for control in column.get_children():
					if control is Control and control.visible and not control is HSeparator:
						content_visible = true
						break
				panel.visible = content_visible
			var height: float = panel.get_combined_minimum_size().y
			if not is_equal_approx(panel.size.y, height):
				panel.size.y = height
	# The current objective is available in Help and the Work log.
	var can_omit_instruction: bool = footer_snapshot_ready and _placement_ready() \
		and not status_refused and not _catalog_open() and not explanation_open
	var redundant_intro: bool = can_omit_instruction and (_native_transmission() \
		and mode in ["inspect", "collector"] \
		and state.get("entities", {}).is_empty() and state.get("transmission_parts", {}).is_empty() \
		and _guided_step({}).tool == "collector" \
		and status_label.text == FIRST_COLLECTOR_HINT)
	status_label.visible = not status_label.text.is_empty() and not redundant_intro
	var right := -18.0
	if object_menu == null:
		var inspector_panel: Control = inspector.get_parent().get_parent()
		right = inspector_panel.get_global_rect().position.x - get_viewport().get_visible_rect().end.x - 18.0 \
			if inspector_panel.visible else -18.0
	if not is_equal_approx(status_footer.offset_right, right):
		status_footer.set_anchor_and_offset(SIDE_RIGHT, 1.0, right)
	var left_anchor := 1.0 if redundant_intro else 0.0
	var narrow_view := get_viewport().get_visible_rect().size.x < 1100.0
	var left_offset: float = right - status_footer.get_combined_minimum_size().x if redundant_intro \
		else 18.0 if narrow_view else 310.0
	if not is_equal_approx(status_footer.anchor_left, left_anchor) or not is_equal_approx(status_footer.offset_left, left_offset):
		status_footer.set_anchor_and_offset(SIDE_LEFT, left_anchor, left_offset)
	var edge := 0.0 if _footer_above_view() else 1.0
	var bottom: float = 18.0 + status_footer.get_combined_minimum_size().y if edge == 0.0 else -30.0 - building_hotbar.size.y
	if not is_equal_approx(status_footer.anchor_bottom, edge) or not is_equal_approx(status_footer.offset_bottom, bottom):
		status_footer.set_anchor_and_offset(SIDE_BOTTOM, edge, bottom)
	var top: float = bottom - status_footer.get_combined_minimum_size().y
	if not is_equal_approx(status_footer.anchor_top, edge) or not is_equal_approx(status_footer.offset_top, top):
		status_footer.set_anchor_and_offset(SIDE_TOP, edge, top)
	if _catalog_open():
		building_hotbar._place_catalog()

func _build_pointed_summary(root: Control) -> void:
	pointed_summary = PanelContainer.new()
	pointed_summary.name = "PointedSummary"
	pointed_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color(0.035, 0.065, 0.075, 0.68)
	surface.set_corner_radius_all(5)
	surface.set_content_margin_all(7)
	pointed_summary.add_theme_stylebox_override("panel", surface)
	root.add_child(pointed_summary)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 1)
	pointed_summary.add_child(column)
	pointed_name = Widgets.label(column, "", 14, Color("f4f5eb"))
	pointed_detail = Widgets.label(column, "", 11, Color("b9ceca"))
	pointed_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pointed_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pointed_summary.visible = false

func _build_object_menu(root: Control, detail_panel: PanelContainer) -> void:
	object_menu_scrim = ColorRect.new()
	object_menu_scrim.name = "ObjectMenuShade"
	object_menu_scrim.color = Color(0.01, 0.02, 0.025, 0.58)
	object_menu_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(object_menu_scrim)
	object_menu_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	object_menu_scrim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			object_menu.hide())
	object_menu_scrim.visible = false
	object_menu = PopupPanel.new()
	object_menu.name = "ObjectMenu"
	object_menu.theme = root.theme.duplicate()
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color(0.035, 0.06, 0.075, 0.97)
	surface.set_corner_radius_all(10)
	object_menu.theme.set_stylebox("panel", "PopupPanel", surface)
	root.add_child(object_menu)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	object_menu.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 12)
	margin.add_child(shell)
	var header := HBoxContainer.new()
	shell.add_child(header)
	object_menu_title = Widgets.label(header, "", 22, Color("f1d7a5"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	object_menu_close = Widgets.button(header, "", object_menu.hide)
	object_menu_close.icon = load("res://opening/assets/menu-icons/close.svg")
	object_menu_close.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	object_menu_close.custom_minimum_size = Vector2(40, 32)
	object_menu_close.tooltip_text = "Close object menu · Esc"
	object_menu_close.accessibility_name = "Close object menu, shortcut Escape"
	shell.add_child(HSeparator.new())
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(columns)
	detail_panel.reparent(columns)
	object_menu_detail_panel = detail_panel
	detail_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	detail_panel.custom_minimum_size = Vector2(220, 0)
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var detail_column := inspector.get_parent() as VBoxContainer
	arrival_assembly_controls.reclaim_spacer = Control.new()
	arrival_assembly_controls.reclaim_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arrival_assembly_controls.reclaim_spacer.visible = false
	detail_column.add_child(arrival_assembly_controls.reclaim_spacer)
	arrival_assembly_controls.reclaim_row.reparent(detail_column, false)
	object_menu_operations = VBoxContainer.new()
	object_menu_operations.custom_minimum_size.x = 420
	object_menu_operations.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	object_menu_operations.size_flags_vertical = Control.SIZE_EXPAND_FILL
	object_menu_operations.add_theme_constant_override("separation", 8)
	columns.add_child(object_menu_operations)
	object_menu_operations_label = Widgets.label(object_menu_operations, "MACHINE ACTIONS", 12, Color("f4bf75"))
	arrival_assembly_scroll.reparent(object_menu_operations)
	arrival_assembly_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arrival_assembly_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arrival_assembly_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	arrival_assembly_controls.custom_minimum_size.x = 410
	arrival_assembly_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arrival_assembly_controls.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	object_menu_operations.visible = false
	object_menu.popup_hide.connect(_on_object_menu_closed)

func _object_menu_open() -> bool:
	return object_menu != null and object_menu.visible

func _pause_menu_open() -> bool:
	return pause_menu != null and pause_menu.visible

func _open_pause_menu() -> void:
	if pause_menu == null or _object_menu_open() or _catalog_open() or explanation_open or manager_log_open:
		return
	_release_character_controls()
	pause_menu_scrim.visible = true
	pause_menu.show()
	pause_resume_button.grab_focus()

func _build_pause_menu(root: Control) -> void:
	pause_menu_scrim = ColorRect.new()
	pause_menu_scrim.name = "PauseMenuShade"
	pause_menu_scrim.color = Color(0.01, 0.02, 0.025, 0.54)
	pause_menu_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_menu_scrim.z_index = 100
	root.add_child(pause_menu_scrim)
	pause_menu_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_menu_scrim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			pause_menu.hide())
	pause_menu_scrim.visible = false
	var center := CenterContainer.new()
	center.name = "PauseMenuCenter"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.z_index = 101
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_menu = PanelContainer.new()
	pause_menu.name = "PauseMenu"
	pause_menu.theme = root.theme.duplicate()
	pause_menu.custom_minimum_size = Vector2(380, 390)
	pause_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color(0.035, 0.06, 0.075, 0.96)
	surface.set_corner_radius_all(10)
	pause_menu.theme.set_stylebox("panel", "PanelContainer", surface)
	center.add_child(pause_menu)
	pause_menu.hide()
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	pause_menu.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	Widgets.label(column, "WORKSITE", 18, Color("f1d7a5"))
	Widgets.label(column, "Esc resumes  ·  F5 saves", 11, Color("b9ceca"))
	var status := VBoxContainer.new()
	status.add_theme_constant_override("separation", 4)
	column.add_child(status)
	for control in [actor_label, power_label, stock_label]:
		control.reparent(status)
	var actions := GridContainer.new()
	actions.columns = 2
	actions.add_theme_constant_override("h_separation", 14)
	actions.add_theme_constant_override("v_separation", 12)
	column.add_child(actions)
	pause_resume_button = _pause_action(actions, "resume", "Resume", "Esc", func(): pause_menu.hide())
	save_button.reparent(actions)
	_style_pause_action(save_button, "save", "Save worksite", "F5")
	load_button.reparent(actions)
	_style_pause_action(load_button, "reopen", "Reopen save", "F9")
	pause_exit_button = _pause_action(actions, "exit", "Exit workshop", "Q", func(): pause_exit_confirmation.popup_centered())
	pause_menu.visibility_changed.connect(func() -> void:
		if not pause_menu.visible:
			pause_menu_scrim.visible = false)
	pause_exit_confirmation = ConfirmationDialog.new()
	pause_exit_confirmation.title = "Exit workshop"
	pause_exit_confirmation.dialog_text = "Unsaved changes will be lost. Save with F5 before exiting."
	pause_exit_confirmation.ok_button_text = "Exit without saving"
	pause_exit_confirmation.confirmed.connect(func(): get_tree().quit())
	root.add_child(pause_exit_confirmation)
	root.resized.connect(_fit_pause_menu.bind(root, margin, actions))
	_fit_pause_menu.call_deferred(root, margin, actions)

func _fit_pause_menu(view: Control, margin: MarginContainer, actions: GridContainer) -> void:
	# A short window needs one row of actions so the shared connection rows
	# and all four worksite actions remain visible together.
	var short_window := view.size.y <= 560.0 and view.size.x >= 600.0
	actions.columns = 4 if short_window else 2
	actions.add_theme_constant_override("h_separation", 8 if short_window else 14)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12 if short_window else 18)
	for button: Button in [pause_resume_button, save_button, load_button, pause_exit_button]:
		button.custom_minimum_size.x = 136 if short_window else 140

func _pause_action(parent: GridContainer, icon_name: String, action_name: String,
		shortcut: String, callback: Callable) -> Button:
	var button := Widgets.button(parent, "", callback)
	_style_pause_action(button, icon_name, action_name, shortcut)
	return button

func _style_pause_action(button: Button, icon_name: String, action_name: String, shortcut: String) -> void:
	button.text = ""
	button.icon = load("res://opening/assets/menu-icons/%s.svg" % icon_name)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = false
	button.custom_minimum_size = Vector2(140, 82)
	button.tooltip_text = "%s  [%s]" % [action_name, shortcut]
	button.accessibility_name = "%s, shortcut %s" % [action_name, shortcut]
	var caption := Label.new()
	caption.text = action_name
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(caption)
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -24
	caption.add_theme_font_size_override("font_size", 11)

func _on_object_menu_closed() -> void:
	object_menu_closed_frame = Engine.get_process_frames()
	object_menu_scrim.visible = false
	object_menu_target = ""
	selected = ""
	_refresh_ui()

func _object_name(target: String) -> String:
	if state.get("entities", {}).has(target):
		return NAMES.get(state.entities[target].kind, str(state.entities[target].kind).capitalize())
	if state.get("foundations", {}).has(target):
		return "Factory floor" if int(state.foundations[target].get("level", 0)) % Geometry.HEIGHT_DENOMINATOR == 0 else "Access step"
	if state.get("transmission_parts", {}).has(target):
		return str(state.transmission_parts[target].get("kind", "Drive part")).replace("_", " ").capitalize()
	if state.get("belt_spans", {}).has(target):
		return "Mechanical belt"
	if target == state.get("fabrication_hub", {}).get("id", ""):
		return "Pod workshop"
	if state.get("placed_components", {}).has(target):
		var component: String = str(state.placed_components[target].get("component", "part"))
		return "Wooden workbench" if component == "wooden_workbench" else component.replace("_", " ").capitalize()
	return ""

func _object_supports_operations(target: String) -> bool:
	if target == state.get("fabrication_hub", {}).get("id", "") and not target.is_empty():
		return true
	if state.get("entities", {}).get(target, {}).get("kind", "") in ["collector", "processor"]:
		return true
	if state.get("placed_components", {}).get(target, {}).get("component", "") == "wooden_workbench":
		return true
	if state.get("placed_components", {}).has(target):
		return true
	for row: Variant in state.get("fabrication_benches", []):
		if row is Dictionary and row.get("id", "") == target:
			return true
	return _is_guided_press_part(target) or _is_collector_frame(target)

func _is_guided_press_part(target: String) -> bool:
	if target.is_empty():
		return false
	for assemblies: Array in [state.get("sliding_press_assemblies", []),
			state.get("guided_press_assemblies", [])]:
		for row: Variant in assemblies:
			if not row is Dictionary:
				continue
			var parts: Variant = row.get("parts", {})
			if row.get("status") == "ready" and (row.get("anvil", "") == target \
					or (parts is Dictionary and parts.values().has(target))):
				return true
	return false

func _is_collector_frame(target: String) -> bool:
	if target.is_empty():
		return false
	for row: Variant in state.get("collector_assemblies", []):
		if row is Dictionary and row.get("parts", {}).get("frame", "") == target:
			return true
	return false

func _pointed_summary_data(screen: Vector2) -> Dictionary:
	if camera == null or not camera.is_inside_tree():
		return {}
	var drop := _screen_loose_material(screen) if mode == "inspect" else {}
	if not drop.is_empty():
		var items: Array[String] = []
		for kind in [["raw", "copper"], ["products", "copper plate"],
				["offcuts", "copper offcut"], ["sheets", "copper sheet"]]:
			var count := int(drop.get(kind[0], 0))
			if count > 0:
				items.append("%d %s" % [count, kind[1]])
		if not drop.get("work_lots", []).is_empty():
			items.append("%d copper workpiece" % drop.work_lots.size())
		return {"name": ", ".join(items), "detail": "E  Pick up"}
	var crank_id := _crank_at_screen(screen)
	if not crank_id.is_empty():
		var connected: bool = not str(state.crank_items[crank_id].get("attached_to", "")).is_empty()
		var detail := "F then click  Reclaim"
		if mode == "deconstruct":
			detail = "Click  Reclaim"
		elif connected:
			detail = "Hold E  Turn · F then click  Reclaim"
		return {"name": "Placed hand crank" if connected else "Disconnected hand crank",
			"detail": detail,
			"target": crank_id}
	var hit := _screen_pick(screen)
	var target := _picked_target_id(hit)
	if _contains_target(state, target):
		var detail := "E  Open"
		if transmission_controls != null and transmission_controls.active_tool == "belt_span" \
				and state.get("transmission_parts", {}).get(target, {}).get("kind", "") == "shaft":
			if transmission_controls._belt_start.is_empty():
				detail = "Click  Select first shaft"
			elif target == transmission_controls._belt_start.get("id", ""):
				detail = "First shaft selected"
			else:
				detail = "Click  Connect belt"
		elif state.get("entities", {}).get(target, {}).get("kind") == "processor":
			detail = "%d ready  ·  E Open" % int(state.get("stock", {}).get("output", 0))
		return {"name": _object_name(target), "detail": detail, "target": target}
	var source_id := _screen_hand_source(screen)
	var source := _hand_source(source_id)
	if not source.is_empty():
		var cut: Dictionary = state.get("manual_cuts", {}).get(client, {})
		if cut.get("target", "") == source_id:
			return {"name": "Timber tree" if source.kind == "tree" else "Ore deposit",
				"detail": "Cutting…"}
		var detail := "Depleted"
		if source.remaining > 0:
			detail = "%d left  ·  Move closer" % source.remaining
			if _hand_source_in_reach(source):
				detail = "%d left  ·  E Harvest" % source.remaining if _hand_source_clear(source_id) else \
					"%d left  ·  Move around" % source.remaining
		return {"name": "Timber tree" if source.kind == "tree" else "Ore deposit",
			"detail": detail}
	return {}

func _refresh_pointed_summary() -> void:
	if pointed_summary == null or camera == null:
		return
	if arrival_reveal_active or explanation_open or manager_log_open or _catalog_open() or _object_menu_open() or _pause_menu_open():
		pointed_summary.visible = false
		return
	var screen := _pointed_screen_position()
	if distance > 0.0 and get_viewport().gui_get_hovered_control() != null:
		pointed_summary.visible = false
		return
	var cache_key := [screen, camera.global_transform, mode, state.get("revision"),
		state.get("order"), transmission_controls.active_tool if transmission_controls != null else "",
		transmission_controls._belt_start if transmission_controls != null else {}]
	if model is NativeWorldModel and cache_key == pointed_summary_cache_key:
		return
	pointed_summary_cache_key = cache_key
	var summary := _pointed_summary_data(screen)
	pointed_summary.visible = not summary.is_empty()
	if summary.is_empty():
		return
	pointed_name.text = summary.name
	pointed_detail.text = summary.detail
	pointed_summary.size = pointed_summary.get_combined_minimum_size()
	var extent := get_viewport().get_visible_rect().size
	pointed_summary.position = Vector2(
		clampf(screen.x + 20.0, 12.0, extent.x - pointed_summary.size.x - 12.0),
		clampf(screen.y + 20.0, 12.0, extent.y - pointed_summary.size.y - 12.0))

func _build_interface() -> void:
	# A revisable opening adapter limit, not a fixed window or a game-world rule.
	get_window().min_size = Vector2i(640, 480)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	arrival_gameplay_canvas = canvas
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = ProductionInterface.make_theme()
	arrival_reveal_canvas = CanvasLayer.new()
	arrival_reveal_canvas.name = "ArrivalReveal"
	arrival_reveal_canvas.layer = 50
	arrival_reveal_canvas.visible = false
	add_child(arrival_reveal_canvas)
	var reveal_root := Control.new()
	reveal_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reveal_root.theme = root.theme
	arrival_reveal_canvas.add_child(reveal_root)
	reveal_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var company := Widgets.label(reveal_root, "MERIDIAN COMBINE  /  FIELD PACKAGE 01", 20, Color("f1d7a5"))
	company.position = Vector2(30, 14)
	var company_style := LabelSettings.new()
	company_style.font_size = 20
	company_style.font_color = Color("f1d7a5")
	company_style.outline_size = 5
	company_style.outline_color = Color("102023")
	company.label_settings = company_style
	arrival_reveal_caption = Widgets.label(reveal_root, "FIELD DESCENT IN PROGRESS", 13, Color("d1ded9"))
	arrival_reveal_caption.position = Vector2(32, 52)
	var caption_style := LabelSettings.new()
	caption_style.font_size = 13
	caption_style.font_color = Color("d1ded9")
	caption_style.outline_size = 4
	caption_style.outline_color = Color("102023")
	arrival_reveal_caption.label_settings = caption_style
	var skip_hint := Widgets.label(reveal_root, "SPACE / ESC  Skip arrival", 13, Color("d1ded9"))
	skip_hint.label_settings = caption_style
	skip_hint.position = Vector2(32, 76)
	fps_label = Widgets.label(root, "FPS --", 13)
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_label.set_anchor_and_offset(SIDE_LEFT, 0.0, 16.0)
	fps_label.set_anchor_and_offset(SIDE_RIGHT, 0.0, 98.0)
	fps_label.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -20.0)
	fps_label.set_anchor_and_offset(SIDE_TOP, 1.0, -44.0)
	var fps_style := LabelSettings.new()
	fps_style.font_size = 13
	fps_style.font_color = Color("e7ede5")
	fps_style.outline_size = 4
	fps_style.outline_color = Color("16242a")
	fps_label.label_settings = fps_style
	building_hotbar = BuildingHotbar.new()
	building_hotbar.configure(self, root)
	tool_buttons.merge(building_hotbar.catalog_buttons)
	parts_label = building_hotbar.parts_label
	catalog_button = building_hotbar.catalog_button
	placement_options_column = Widgets.panel(root, Vector2.ZERO, Vector2(302, 0))
	Widgets.hud_surface(placement_options_column, 0.66)
	placement_options_panel = placement_options_column.get_parent() as PanelContainer
	placement_options_panel.name = "PlacementOptions"
	placement_options_panel.visible = false
	placement_options_title = Widgets.label(placement_options_column, "PLACE", 17, Color("edcc8d"))
	placement_options_hint = Widgets.label(placement_options_column, "Left click to build · Esc to cancel", 13, Color("a3b8b4"))
	placement_options_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	placement_options_hint.custom_minimum_size.x = 260
	rotation_button = Widgets.button(placement_options_column, "Rotate [R]", _rotate_building)
	rotation_button.visible = false
	placement_options_axis = Widgets.button(placement_options_column, "Axle: X", _cycle_placement_axis)
	placement_options_axis.visible = false
	foundation_level_controls = HBoxContainer.new()
	placement_options_column.add_child(foundation_level_controls)
	Widgets.button(foundation_level_controls, "−", _adjust_foundation_level.bind(-1))
	foundation_level_label = Widgets.label(foundation_level_controls, _construction_height_text(), 14)
	Widgets.button(foundation_level_controls, "+", _adjust_foundation_level.bind(1))
	foundation_level_controls.visible = false
	foundation_steps_toggle = CheckButton.new()
	foundation_steps_toggle.text = "Access steps"
	foundation_steps_toggle.tooltip_text = "Use one height unit for walking steps. Normal height changes move one foundation thickness. Machines need whole-tile factory floors; turning this off snaps the selected height to one."
	foundation_steps_toggle.toggled.connect(_set_foundation_steps)
	placement_options_column.add_child(foundation_steps_toggle)
	foundation_steps_toggle.visible = false
	wheel_size_controls = HBoxContainer.new()
	placement_options_column.add_child(wheel_size_controls)
	Widgets.button(wheel_size_controls, "−", _adjust_wheel_size.bind(-1))
	wheel_size_label = Widgets.label(wheel_size_controls, "Wheel diameter: 3 squares", 14)
	Widgets.button(wheel_size_controls, "+", _adjust_wheel_size.bind(1))
	wheel_size_controls.visible = false
	foundation_area_toggle = CheckButton.new()
	foundation_area_toggle.text = "Area (two corners)"
	foundation_area_toggle.toggled.connect(func(enabled: bool) -> void:
		foundation_area_mode = enabled
		foundation_area_started = false)
	placement_options_column.add_child(foundation_area_toggle)
	foundation_area_toggle.visible = false
	var right := Widgets.panel(root, Vector2(932, 18), Vector2(255, 0))
	Widgets.hud_surface(right, 0.58)
	var right_panel: Control = right.get_parent()
	# Set the far anchor first so the near anchor is not clamped.
	right_panel.set_anchor_and_offset(SIDE_RIGHT, 1.0, -18)
	right_panel.set_anchor_and_offset(SIDE_LEFT, 1.0, -273)
	right_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	# The actor/connection rows identify the physical worksite. Leave room
	# for a selected press and pending-server advice above the status panel.
	right.add_theme_constant_override("separation", 6)
	inspector_title = Widgets.label(right, "SELECTED", 12, Color("f4bf75"))
	actor_label = Widgets.label(right, "", 11, Color("a3b8b4"))
	power_label = Widgets.label(right, "", 14, Color("dfbc76"))
	stock_label = Widgets.label(right, "", 16)
	inspector = Widgets.label(right, "", 13)
	inspector.custom_minimum_size.x = 195
	inspector.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspection_actions = HBoxContainer.new()
	inspection_actions.add_theme_constant_override("separation", 5)
	right.add_child(inspection_actions)
	retrieve_button = Widgets.button(inspection_actions, "Collect  Ctrl+R", _retrieve)
	Widgets.accent_button(retrieve_button)
	remove_button = Widgets.button(inspection_actions, "Remove  Del", _remove_selected)
	for action in [retrieve_button, remove_button]:
		action.custom_minimum_size.y = 30
		action.add_theme_font_size_override("font_size", 12)
	recovery_actions = RecoveryActions.new()
	right.add_child(recovery_actions)
	recovery_actions.configure(self)
	if developer_material_tools:
		loose_material_controls = RecoveryActions.LooseMaterialControls.new()
		right.add_child(loose_material_controls)
		loose_material_controls.configure(self)
	arrival_assembly_scroll = ScrollContainer.new()
	arrival_assembly_scroll.name = "ArrivalWorkshopScroll"
	arrival_assembly_scroll.custom_minimum_size.y = 260
	right.add_child(arrival_assembly_scroll)
	arrival_assembly_controls = RecoveryActions.ArrivalAssemblyControls.new()
	arrival_assembly_scroll.add_child(arrival_assembly_controls)
	arrival_assembly_controls.configure(self)
	arrival_assembly_scroll.visible = false
	right.add_child(HSeparator.new())
	save_button = Widgets.button(right, "Save worksite  [F5]", _save_worksite)
	load_button = Widgets.button(right, "Load worksite  [F9]", _load_worksite)
	_build_object_menu(root, right_panel as PanelContainer)
	if loose_material_controls != null:
		loose_material_controls.text = "DEBUG material"
		loose_material_controls.accessibility_name = "Developer material commands, shortcut Control L"
	_build_pause_menu(root)
	_build_pointed_summary(root)
	var bottom := Widgets.panel(root, Vector2(310, 694), Vector2(952, 88))
	Widgets.hud_surface(bottom, 0.64, 7)
	var bottom_panel: Control = bottom.get_parent()
	status_footer = bottom_panel
	bottom_panel.set_anchor_and_offset(SIDE_RIGHT, 1.0, -18)
	bottom_panel.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -128)
	bottom_panel.set_anchor_and_offset(SIDE_TOP, 1.0, -216)
	bottom_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	status_label = Widgets.label(bottom, "", 14)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_label = Widgets.label(bottom, "B catalog · 1–8 build · E open · F dismantle · C link · J log · H help", 12, Color("bfd1cc"))
	developer_mode_label = Widgets.label(bottom, "F3  FAST", 11, Color("64777a"))
	developer_mode_label.focus_mode = Control.FOCUS_ALL
	bottom_panel.minimum_size_changed.connect(_queue_footer_fit)
	bottom_panel.resized.connect(_queue_footer_fit)
	for column: Control in [right]:
		column.minimum_size_changed.connect(_queue_footer_fit)
	var lesson_column := Widgets.panel(root, Vector2(346, 18), Vector2(600, 192))
	help_panel = lesson_column.get_parent()
	help_panel.set_anchor_and_offset(SIDE_RIGHT, 0.5, 306)
	help_panel.set_anchor_and_offset(SIDE_LEFT, 0.5, -294)
	help_title = Widgets.label(lesson_column, "", 17, Color("edcc8d"))
	help_body = Widgets.label(lesson_column, "", 16)
	help_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_close_button = Widgets.button(lesson_column, "Return to work  [H / Esc]", _toggle_explanation)
	help_close_button.tooltip_text = "Close Help and return to the worksite."
	help_panel.visible = false
	_build_manager_log()

func _build_manager_log() -> void:
	manager_log_layer = CanvasLayer.new()
	manager_log_layer.name = "MeridianWorkLog"
	manager_log_layer.layer = 20
	manager_log_layer.visible = false
	add_child(manager_log_layer)
	var log_root := Control.new()
	log_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	manager_log_layer.add_child(log_root)
	log_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	log_root.theme = ProductionInterface.make_theme()
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.05, 0.58)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	log_root.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := Widgets.panel(log_root, Vector2.ZERO, Vector2(550, 480))
	column.add_theme_constant_override("separation", 8)
	var panel := column.get_parent() as PanelContainer
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	column.reparent(scroll)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	manager_log_panel = panel
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -275.0
	panel.offset_right = 275.0
	panel.offset_top = -240.0
	panel.offset_bottom = 240.0
	Widgets.label(column, "MERIDIAN COMBINE  /  WORK LOG", 19, Color("f1d7a5"))
	Widgets.label(column, "Field Operations Manager · Shift 01", 13, Color("a9c3bb"))
	column.add_child(HSeparator.new())
	for entry in [
		"00  LANDFALL\nLandfall confirmed. Your office is now the part of the planet under your boots.",
		"01  FIELD KIT\nThe kit makes tools. The tools make a factory. Corporate has provided the kit.",
		"02  FIRST WORKSHOP\nForm one plate from local stock and collect it in your inventory."]:
		var line := Widgets.label(column, entry, 15)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size.x = 496.0
	manager_log_completion_entry = Widgets.label(column,
		"03  FIRST WORKSHOP COMPLETE\nYou collected your first formed plate. Corporate has filed your next shift under 'voluntary.'", 15,
		Color("f1d7a5"))
	manager_log_completion_entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	manager_log_completion_entry.custom_minimum_size.x = 496.0
	manager_log_completion_entry.visible = false
	manager_log_projects = VBoxContainer.new()
	manager_log_projects.add_theme_constant_override("separation", 6)
	column.add_child(manager_log_projects)
	for project in [
		["wheel", "Run the familiar press from the river with a waterwheel, Shaft and cogwheels."],
		["collector", "Assemble a finite ore collector at the deposit."],
		["belt", "Then route its copper by belt to a powered press."]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		manager_log_projects.add_child(row)
		var icon := TextureRect.new()
		icon.texture = load("res://opening/assets/build-icons/%s.svg" % project[0])
		icon.custom_minimum_size = Vector2(26, 26)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var description := Widgets.label(row, project[1], 14)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	manager_log_projects.visible = false
	manager_log_current = Widgets.label(column, "CURRENT FIELD CUE\nInspect the worksite.", 15, Color("f1d7a5"))
	manager_log_current.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var close_log := Widgets.button(column, "Return to work  [J / Esc]", _toggle_manager_log)
	Widgets.accent_button(close_log)
