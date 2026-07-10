extends CanvasLayer

signal player_hit

const Spear2D := preload("res://hazards/spear_2d.gd")

const SPEAR_SPEED: float = 900.0
const LOW_HEIGHT_FRACTION: float = 0.78
const HIGH_HEIGHT_FRACTION: float = 0.60
const HIT_ZONE_HALF_WIDTH: float = 40.0
const OFFSCREEN_MARGIN: float = 120.0

@onready var player: CharacterBody3D = $"../Player"


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


# A spear "hits" when it crosses the character at screen center while
# the required dodge is not active: low spears need the player airborne,
# high spears need the player ducking.
func _physics_process(_delta: float) -> void:
	var center_x := get_viewport().get_visible_rect().size.x * 0.5

	for child in get_children():
		var spear := child as Spear2D
		if spear == null or spear.checked:
			continue
		if absf(spear.position.x - center_x) > HIT_ZONE_HALF_WIDTH:
			continue

		spear.checked = true
		var dodged: bool = player.is_ducking() if spear.is_high else not player.is_on_floor()
		if not dodged:
			player_hit.emit()
			_clear_spears()
			return


func _clear_spears() -> void:
	for child in get_children():
		if child is Spear2D:
			child.queue_free()
