extends CanvasLayer

# The level name, huge and bold with a drop shadow, stamped over the
# frozen frame in the middle of a level intro.

var _root: Control


func setup(kicker: String, title: String) -> void:
	layer = 20
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)

	# Font sizes are tuned for the 648-high base window: scale with the
	# real window height, then shrink long lines to fit the width.
	var win := Vector2(DisplayServer.window_get_size())
	var font_scale := win.y / 648.0 if win.y > 0.0 else 1.0
	box.add_child(_make_label(kicker, int(44 * font_scale), win.x))
	box.add_child(_make_label(title, int(112 * font_scale), win.x))


func set_opacity(alpha: float) -> void:
	_root.modulate.a = alpha


func _make_label(text: String, size: int, max_width: float = 0.0) -> Label:
	var label := Label.new()
	# Callers pass already-translated titles; translating again could
	# collide with an unrelated key, and the width math below needs the
	# final string anyway.
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var font := SystemFont.new()
	# Liberation Sans is the Linux stand-in for Arial (weight 900 picks
	# its bold face).
	font.font_names = PackedStringArray(["Arial Black", "Arial", "Liberation Sans", "Segoe UI"])
	font.font_weight = 900
	font.fallbacks = GameManager.cjk_fallback_fonts(900)
	# Long titles (Level 1!) would spill past the window edges.
	if max_width > 0.0:
		var line_width := font.get_string_size(text,
				HORIZONTAL_ALIGNMENT_CENTER, -1, size).x
		if line_width > max_width * 0.94:
			size = maxi(int(size * max_width * 0.94 / line_width), 1)
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.5))
	label.add_theme_color_override("font_outline_color", Color(0.2, 0.12, 0.04))
	label.add_theme_constant_override("outline_size", size / 12)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", size / 14)
	label.add_theme_constant_override("shadow_offset_y", size / 11)
	label.add_theme_constant_override("shadow_outline_size", size / 16)
	return label
