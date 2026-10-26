extends RefCounted
## Draw styles only. Effective content metrics remain the engine defaults.
static var shared_theme: Theme

static func _style(source: StyleBox, fill: Color, line: Color, focus: bool = false) -> StyleBoxFlat:
	var style := source.duplicate() as StyleBoxFlat
	if style == null:
		style = StyleBoxFlat.new()
	for side in range(4):
		# get_margin resolves a negative raw content margin through the old
		# border. Freeze that effective metric before drawing new borders.
		style.set_content_margin(side, source.get_margin(side))
	style.bg_color = fill
	style.border_color = line
	style.set_border_width_all(2 if focus else 1)
	style.set_corner_radius_all(4)
	style.corner_detail = 4
	style.draw_center = not focus
	return style

static func make_theme() -> Theme:
	if shared_theme != null:
		return shared_theme
	var theme := Theme.new()
	theme.default_font_size = 15
	var original := ThemeDB.get_default_theme()
	var fills := {"normal": Color("18252b"), "hover": Color("294048"),
		"pressed": Color("644a29"), "hover_pressed": Color("735935"), "disabled": Color("172126")}
	var borders := {"normal": Color("52676b"), "hover": Color("a1bdba"),
		"pressed": Color("e4ad61"), "hover_pressed": Color("f6c77f"), "disabled": Color("35454a")}
	for control_type in ["Button", "MenuButton"]:
		# Resolve the actual inherited defaults. MenuButton has its own
		# zero-padding styles; borrowing Button metrics would widen it.
		var probe: Button = MenuButton.new() if control_type == "MenuButton" else Button.new()
		for name_value in fills:
			theme.set_stylebox(name_value, control_type, _style(probe.get_theme_stylebox(name_value), fills[name_value], borders[name_value]))
		theme.set_stylebox("focus", control_type, _style(probe.get_theme_stylebox("focus"), Color.TRANSPARENT, Color("efc78a"), true))
		for name_value in ["font_color", "font_hover_color", "font_focus_color"]:
			theme.set_color(name_value, control_type, Color("f1f5f0"))
		for name_value in ["font_pressed_color", "font_hover_pressed_color"]:
			theme.set_color(name_value, control_type, Color("fff3de"))
		theme.set_color("font_disabled_color", control_type, Color("a1b2ad"))
		probe.free()
	var separator := original.get_stylebox("separator", "HSeparator").duplicate() as StyleBox
	if separator is StyleBoxLine:
		separator.color = Color("41565e")
	theme.set_stylebox("separator", "HSeparator", separator)
	shared_theme = theme
	return theme
