extends CanvasLayer

signal player_hit(hit_high: bool)

const Spear2D := preload("res://hazards/spear_2d.gd")

const SPEAR_SPEED: float = 900.0
# The first spears fly slowly and each one is a little faster, reaching
# the full speed on the RAMP_COUNT-th spear, so the player can ease in.
const SPEAR_SPEED_FIRST: float = 620.0
const RAMP_COUNT: int = 4
# World-space heights above the character's feet; projected to screen
# at spawn time so the lanes track the character at any camera pitch.
# Tuned to the Level-1 archaeologist: the high spear grazes the hat brim
# (~1.75 m) and the low spear the ankles (~0.12 m).
const LOW_ANKLE_HEIGHT: float = 0.12
const HIGH_HAT_HEIGHT: float = 1.80
const OFFSCREEN_MARGIN: float = 120.0

# Drawn spear extent around its origin (see spear_2d.gd _draw), in pixels
# at the 1152x648 baseline window the spears were tuned for. Spears are
# scaled with the window height so they keep their size relative to the
# 3D character at any resolution, and their speed is derived from the
# baseline flight time so the reaction window does not depend on the
# window shape (a 21:9 screen is much wider relative to its height).
const BASE_VIEW_WIDTH: float = 1152.0
const BASE_VIEW_HEIGHT: float = 648.0
const SPEAR_TIP: float = 92.0
const SPEAR_TAIL: float = 80.0
const CHARACTER_HALF_WIDTH: float = 35.0

@onready var player: CharacterBody3D = $"../Player"

var _spawn_count: int = 0


func has_active_spears() -> bool:
	for child in get_children():
		if child is Spear2D:
			return true
	return false


# Restart the difficulty ramp so the next attempt eases in from slow again.
func reset_ramp() -> void:
	_spawn_count = 0


func spawn_spear(is_high: bool, from_left: bool) -> void:
	var view_size := get_viewport().get_visible_rect().size
	var s := view_size.y / BASE_VIEW_HEIGHT
	var spear := Spear2D.new()
	spear.is_high = is_high
	spear.direction = 1.0 if from_left else -1.0
	# Ramp the speed up over the first RAMP_COUNT spears. The px/s value
	# is what the spear would fly at the baseline window; convert it to
	# the time it needs from the edge to the center there, then pick the
	# actual speed so this window is crossed in exactly that time.
	var t := clampf(float(_spawn_count) / float(RAMP_COUNT - 1), 0.0, 1.0)
	var base_speed := lerpf(SPEAR_SPEED_FIRST, SPEAR_SPEED, t)
	var flight_time := (BASE_VIEW_WIDTH * 0.5 + OFFSCREEN_MARGIN) / base_speed
	spear.speed = (view_size.x * 0.5 + OFFSCREEN_MARGIN * s) / flight_time
	_spawn_count += 1
	spear.scale = Vector2(spear.direction * s, s)
	spear.position = Vector2(
		-OFFSCREEN_MARGIN * s if from_left else view_size.x + OFFSCREEN_MARGIN * s,
		_lane_screen_y(is_high)
	)
	add_child(spear)


# The Visual node's origin sits at the character's feet, standing or
# ducking; project the lane height next to it onto the screen.
func _lane_screen_y(is_high: bool) -> float:
	var feet: Vector3 = player.get_node("Visual").global_position
	var lane := feet + Vector3.UP * (HIGH_HAT_HEIGHT if is_high else LOW_ANKLE_HEIGHT)
	return get_viewport().get_camera_3d().unproject_position(lane).y


# The dodge must be active for as long as any part of the drawn spear
# overlaps the character at screen center: low spears need the player
# airborne, high spears need the player ducking. Jumping after the tip
# has already reached the character is too late.
func _physics_process(_delta: float) -> void:
	var center_x := get_viewport().get_visible_rect().size.x * 0.5

	for child in get_children():
		var spear := child as Spear2D
		if spear == null:
			continue

		var s := absf(spear.scale.y)
		var lead := spear.position.x + spear.direction * SPEAR_TIP * s
		var tail := spear.position.x - spear.direction * SPEAR_TAIL * s
		if maxf(lead, tail) < center_x - CHARACTER_HALF_WIDTH * s:
			continue
		if minf(lead, tail) > center_x + CHARACTER_HALF_WIDTH * s:
			continue

		var dodged: bool = player.is_ducking() if spear.is_high else not player.is_on_floor()
		if not dodged:
			player_hit.emit(spear.is_high)
			_clear_spears()
			return


func _clear_spears() -> void:
	for child in get_children():
		if child is Spear2D:
			child.queue_free()
