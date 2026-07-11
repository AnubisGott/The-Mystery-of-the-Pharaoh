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

	box.add_child(_make_label(kicker, 44))
	box.add_child(_make_label(title, 112))


func set_opacity(alpha: float) -> void:
	_root.modulate.a = alpha


func _make_label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Arial Black", "Arial", "Segoe UI"])
	font.font_weight = 900
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
