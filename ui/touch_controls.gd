extends CanvasLayer

# On-screen controls for the mobile port. The round buttons are
# TouchScreenButtons - real multi-touch, so holding one never blocks
# another - and they press the regular input actions, which keeps the
# player physics and all level logic unchanged. Each level adds only
# the buttons its mobile control scheme needs (see the Android port
# design), and only in touch mode (GameManager.touch_mode).

const RADIUS: float = 64.0
# The auto-run levels have only two buttons: they sit big and centered
# on either side, under the thumbs.
const SIDE_RADIUS: float = 92.0
const PAUSE_RADIUS: float = 40.0
const MARGIN: float = 26.0
const GAP: float = 20.0

var _anchors: Array[Dictionary] = []


func _init() -> void:
	name = "TouchControls"
	layer = 15


func _ready() -> void:
	get_viewport().size_changed.connect(_layout)
	_layout()


# A round action button. `right` picks the screen side; `col` counts
# button widths inward from that side, `row` upward from the bottom.
# An empty `action` makes a button the level polls itself (is_pressed).
func add_button(text: String, action: String, right: bool, col: int = 0, row: int = 0,
		radius: float = RADIUS, center_v: bool = false) -> TouchScreenButton:
	var button := _make_round_button(text, radius, 30 if radius >= RADIUS else 22)
	button.action = action
	_anchors.append({"node": button, "right": right, "col": col, "row": row,
			"top": false, "center_v": center_v})
	_layout()
	return button


# Small pause toggle in the top-right corner. Routed through a real
# input event so the pause menu's _unhandled_input sees the action.
func add_pause_button() -> void:
	var button := _make_round_button("II", PAUSE_RADIUS, 24)
	button.pressed.connect(_emit_pause)
	_anchors.append({"node": button, "right": true, "col": 0, "row": 0, "top": true,
			"center_v": false})
	_layout()


func _emit_pause() -> void:
	var event := InputEventAction.new()
	event.action = "pause"
	event.pressed = true
	Input.parse_input_event(event)


func _make_round_button(text: String, radius: float, font_size: int) -> TouchScreenButton:
	var button := TouchScreenButton.new()
	button.texture_normal = _circle(radius, 0.32)
	button.texture_pressed = _circle(radius, 0.62)
	add_child(button)

	var label := Label.new()
	label.text = text
	label.size = Vector2(radius * 2.0, radius * 2.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Long words (BENUTZEN, ПРЫЖОК) must not spill over the button.
	if text.length() > 4:
		font_size = maxi(int(font_size * 4.0 / float(text.length())), 13)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.12, 0.09, 0.05, 0.95))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
	return button


func _circle(radius: float, alpha: float) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.93, 0.78, alpha))
	gradient.add_point(0.88, Color(1.0, 0.93, 0.78, alpha))
	gradient.set_color(gradient.get_point_count() - 1, Color(1.0, 0.93, 0.78, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = int(radius * 2.0)
	texture.height = int(radius * 2.0)
	return texture


func _layout() -> void:
	if not is_inside_tree():
		return
	var size := get_viewport().get_visible_rect().size
	for anchor in _anchors:
		var button: TouchScreenButton = anchor["node"]
		var diameter: float = button.texture_normal.width
		var step := diameter + GAP
		var x: float
		if anchor["right"]:
			x = size.x - MARGIN - diameter - anchor["col"] * step
		else:
			x = MARGIN + anchor["col"] * step
		var y: float
		if anchor.get("center_v", false):
			y = (size.y - diameter) / 2.0
		elif anchor["top"]:
			y = MARGIN + anchor["row"] * step
		else:
			y = size.y - MARGIN - diameter - anchor["row"] * step
		button.position = Vector2(x, y)
