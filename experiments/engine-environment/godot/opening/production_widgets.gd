extends RefCounted
## Common widget construction. Callers supply content and callbacks explicitly.

static func label(parent: Node, words: String, size: int = 16, color: Color = Color("dde5d9")) -> Label:
	var label := Label.new()
	label.text = words
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

static func button(parent: Node, words: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = words
	button.custom_minimum_size.y = 37
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

static func accent_button(button: Button) -> void:
	for state_name in ["normal", "hover", "pressed", "hover_pressed"]:
		var style := button.get_theme_stylebox(state_name).duplicate() as StyleBoxFlat
		style.bg_color = Color("614721") if state_name in ["normal", "pressed"] else Color("806036")
		style.border_color = Color("e9b873")
		button.add_theme_stylebox_override(state_name, style)
	button.add_theme_color_override("font_color", Color("fff5df"))
	button.add_theme_color_override("font_hover_color", Color("fff5df"))

static func panel(parent: Node, at: Vector2, dimensions: Vector2) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.position = at
	panel.size = dimensions
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.092, 0.112, 0.94)
	style.border_color = Color("52676b")
	style.set_corner_radius_all(7)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 15
	style.content_margin_bottom = 15
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	panel.add_child(column)
	return column

static func hud_surface(column: VBoxContainer, opacity: float, padding: int = 10) -> void:
	var panel := column.get_parent() as PanelContainer
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.085, opacity)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(padding)
	panel.add_theme_stylebox_override("panel", style)
	column.add_theme_constant_override("separation", 5)
