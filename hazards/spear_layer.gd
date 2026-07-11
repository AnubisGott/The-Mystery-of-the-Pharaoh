extends CanvasLayer

signal player_hit(hit_high: bool)

const Spear2D := preload("res://hazards/spear_2d.gd")

const SPEAR_SPEED: float = 900.0
# The first spears fly slowly and each one is a little faster, reaching
# the full speed on the RAMP_COUNT-th spear, so the player can ease in.
const SPEAR_SPEED_FIRST: float = 430.0
const RAMP_COUNT: int = 8
# World-space heights above the character's feet; projected to screen
# at spawn time so the lanes track the character at any camera pitch.
# Tuned to the Level-1 archaeologist: the high spear grazes the hat brim
# (~1.75 m) and the low spear the ankles (~0.12 m).
const LOW_ANKLE_HEIGHT: float = 0.12
const HIGH_HAT_HEIGHT: float = 1.80
const OFFSCREEN_MARGIN: float = 120.0

# Drawn spear extent around its origin (see spear_2d.gd _draw).
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


func spawn_spear(is_high: bool, from_left: bool) -> void:
	var view_size := get_viewport().get_visible_rect().size
	var spear := Spear2D.new()
	spear.is_high = is_high
	spear.direction = 1.0 if from_left else -1.0
	# Ramp the speed up over the first RAMP_COUNT spears.
	var t := clampf(float(_spawn_count) / float(RAMP_COUNT - 1), 0.0, 1.0)
	spear.speed = lerpf(SPEAR_SPEED_FIRST, SPEAR_SPEED, t)
	_spawn_count += 1
	spear.scale.x = spear.direction
	spear.position = Vector2(
		-OFFSCREEN_MARGIN if from_left else view_size.x + OFFSCREEN_MARGIN,
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

		var lead := spear.position.x + spear.direction * SPEAR_TIP
		var tail := spear.position.x - spear.direction * SPEAR_TAIL
		if maxf(lead, tail) < center_x - CHARACTER_HALF_WIDTH:
			continue
		if minf(lead, tail) > center_x + CHARACTER_HALF_WIDTH:
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
