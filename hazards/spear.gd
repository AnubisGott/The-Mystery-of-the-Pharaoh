extends Area3D

signal player_hit

const MAX_TRAVEL: float = 34.0

var direction: Vector3 = Vector3.RIGHT
var speed: float = 9.0

var _start: Vector3


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_start = global_position

	# The scene's tip points toward +X; flip when flying the other way.
	if direction.x < 0.0:
		rotation.y = PI


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	if global_position.distance_to(_start) > MAX_TRAVEL:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_hit.emit()
		queue_free()
