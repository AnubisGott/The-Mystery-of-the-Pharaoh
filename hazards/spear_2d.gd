extends Node2D

var is_high: bool = false
var direction: float = 1.0
var speed: float = 900.0
var checked: bool = false


func _physics_process(delta: float) -> void:
	position.x += direction * speed * delta

	var width := get_viewport_rect().size.x
	if position.x < -150.0 or position.x > width + 150.0:
		queue_free()


func _draw() -> void:
	# Drawn pointing right; flying left is mirrored via scale.x.
	draw_line(Vector2(-80.0, 0.0), Vector2(55.0, 0.0), Color(0.45, 0.3, 0.16), 7.0)
	var tip := PackedVector2Array([Vector2(55.0, -9.0), Vector2(92.0, 0.0), Vector2(55.0, 9.0)])
	draw_colored_polygon(tip, Color(0.75, 0.75, 0.78))
