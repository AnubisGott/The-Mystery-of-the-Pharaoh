extends CanvasLayer

signal player_hit

const Spear2D := preload("res://hazards/spear_2d.gd")

const SPEAR_SPEED: float = 900.0
const LOW_HEIGHT_FRACTION: float = 0.86
const HIGH_HEIGHT_FRACTION: float = 0.60
const OFFSCREEN_MARGIN: float = 120.0

# Drawn spear extent around its origin (see spear_2d.gd _draw).
const SPEAR_TIP: float = 92.0
const SPEAR_TAIL: float = 80.0
const CHARACTER_HALF_WIDTH: float = 35.0

@onready var player: CharacterBody3D = $"../Player"


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
	spear.speed = SPEAR_SPEED
	spear.scale.x = spear.direction
	spear.position = Vector2(
		-OFFSCREEN_MARGIN if from_left else view_size.x + OFFSCREEN_MARGIN,
		view_size.y * (HIGH_HEIGHT_FRACTION if is_high else LOW_HEIGHT_FRACTION)
	)
	add_child(spear)


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
			player_hit.emit()
			_clear_spears()
			return


func _clear_spears() -> void:
	for child in get_children():
		if child is Spear2D:
			child.queue_free()
