extends SceneTree
const Widgets = preload("res://opening/production_widgets.gd")
## Presentation styles and layout metrics only. No game or desktop input.
const Opening = preload("res://opening/opening.gd")
const Styles = preload("res://opening/production_interface.gd")
const STATES := ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]
var checks := 0
var failed := false
var callbacks := 0
var minimum_contrast := INF

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)

func clicked() -> void:
	callbacks += 1

func luminance(color: Color) -> float:
	var linear := color.srgb_to_linear()
	return linear.r * 0.2126 + linear.g * 0.7152 + linear.b * 0.0722

func contrast(a: Color, b: Color) -> float:
	var first := luminance(a)
	var second := luminance(b)
	return (maxf(first, second) + 0.05) / (minf(first, second) + 0.05)

func check_styles(old: Button, fresh: Button) -> void:
	for state in STATES:
		var before := old.get_theme_stylebox(state)
		var after := fresh.get_theme_stylebox(state)
		verify(before != after, "Production styles do not modify the shared engine defaults.")
		verify(before.get_minimum_size() == after.get_minimum_size(),
			"Every drawing state preserves its independently resolved minimum style size.")
		for side in range(4):
			verify(before.get_margin(side) == after.get_margin(side),
				"Effective content padding is unchanged even where the engine uses border fallback.")
		if state != "focus":
			var color_name: String = {"normal": "font_color", "hover": "font_hover_color",
				"pressed": "font_pressed_color", "hover_pressed": "font_hover_pressed_color",
				"disabled": "font_disabled_color"}[state]
			var ratio := contrast(fresh.get_theme_color(color_name), after.bg_color)
			minimum_contrast = minf(minimum_contrast, ratio)
			verify(ratio >= 4.5, "Assigned opaque text/background colors retain a useful numerical contrast margin.")
		else:
			verify(not after.draw_center and after.border_color.a == 1.0,
				"Keyboard focus remains an explicit outline that cannot obscure the content.")
	verify(old.get_theme_font("font") == fresh.get_theme_font("font")
		and old.get_theme_font_size("font_size") == fresh.get_theme_font_size("font_size"),
		"The style reuses the exact inherited font and size.")

func check_buttons() -> void:
	var old_root := Control.new()
	var new_root := Control.new()
	var previous := Theme.new()
	previous.default_font_size = 15
	old_root.theme = previous
	new_root.theme = Styles.make_theme()
	root.add_child(old_root)
	root.add_child(new_root)
	var view := Opening.new()
	for control_type in ["Button", "MenuButton"]:
		var old: Button = MenuButton.new() if control_type == "MenuButton" else Button.new()
		var fresh: Button = MenuButton.new() if control_type == "MenuButton" else Button.new()
		old_root.add_child(old)
		new_root.add_child(fresh)
		check_styles(old, fresh)
		for text in ["Collect plate  [R]", "Dismantle selected", "Shaft  [G]    ·    3 carried", "X / Y / Z axis", "Material → Press"]:
			old.text = text
			fresh.text = text
			for state in [0, 1, 2]:
				old.toggle_mode = true
				fresh.toggle_mode = true
				old.button_pressed = state == 1
				fresh.button_pressed = state == 1
				old.disabled = state == 2
				fresh.disabled = state == 2
				verify(old.get_combined_minimum_size() == fresh.get_combined_minimum_size(),
					"Literal ordinary/native menu text keeps its baseline width and height in every state.")
	var old_column := Widgets.panel(old_root, Vector2(18, 18), Vector2(275, 620))
	var new_column := Widgets.panel(new_root, Vector2(18, 18), Vector2(275, 620))
	var old_button := Widgets.button(old_column, "Confirm four plates", clicked)
	var new_button := Widgets.button(new_column, "Confirm four plates", clicked)
	verify(old_button.custom_minimum_size == Vector2(0, 37)
		and old_button.get_combined_minimum_size() == new_button.get_combined_minimum_size(),
		"The actual worksite button helper retains its 37-pixel control contract through inheritance.")
	var panel: PanelContainer = new_column.get_parent()
	var box := panel.get_theme_stylebox("panel")
	verify(box.get_margin(SIDE_LEFT) == 16 and box.get_margin(SIDE_RIGHT) == 16
		and box.get_margin(SIDE_TOP) == 15 and box.get_margin(SIDE_BOTTOM) == 15,
		"Panel content and the existing layout separation remain literal unchanged values.")
	verify(new_column.get_theme_constant("separation") == 9, "The panel helper does not change its content spacing.")
	var before_focus: StyleBox = old_button.get_theme_stylebox("focus")
	var before_color: Color = (old_button.get_theme_stylebox("normal") as StyleBoxFlat).bg_color
	verify(Styles.make_theme() == new_root.theme and old_button.get_theme_stylebox("focus") == before_focus
		and (old_button.get_theme_stylebox("normal") as StyleBoxFlat).bg_color == before_color,
		"Repeated theme use shares the private resources and leaves the original theme intact.")
	verify(callbacks == 0 and view.model == null and view.actor_world == null and view.request_sequence == 0,
		"Style creation, state changes and helper assembly send no input or command.")
	view.free()
	old_root.free()
	new_root.free()

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	check_buttons()
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
		"minimum_assigned_color_contrast": minimum_contrast, "rendered_quality": "not_assessed",
		"gui_input": "not_used", "desktop": "not_used"}))
	quit(1 if failed else 0)
