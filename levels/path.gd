extends Node3D

# Walkable ground rectangles (x, z) matching the visible path segments.
const PATH_RECTS: Array[Rect2] = [
	Rect2(-1.5, 10.0, 3.0, 10.0),
	Rect2(-1.5, 7.0, 12.0, 3.0),
	Rect2(7.5, -3.5, 3.0, 12.0),
	Rect2(-9.0, -5.5, 18.0, 3.0),
	Rect2(-9.0, -16.0, 3.0, 12.0),
	Rect2(-9.0, -18.5, 12.0, 3.0),
	Rect2(0.0, -25.0, 3.0, 8.0),
]

@onready var player: CharacterBody3D = $Player


func _physics_process(_delta: float) -> void:
	var position_2d := Vector2(player.global_position.x, player.global_position.z)
	var clamped := _closest_point_on_path(position_2d)
	if clamped != position_2d:
		player.global_position.x = clamped.x
		player.global_position.z = clamped.y


func _closest_point_on_path(point: Vector2) -> Vector2:
	var best_point := point
	var best_distance := INF

	for rect in PATH_RECTS:
		if rect.has_point(point):
			return point

		var candidate := point.clamp(rect.position, rect.end)
		var distance := candidate.distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best_point = candidate

	return best_point
