extends Area3D

signal collected

@export var spin_speed: float = 1.8

var _was_collected: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	rotate_y(spin_speed * delta)


func _on_body_entered(body: Node3D) -> void:
	if _was_collected or not body.is_in_group("player"):
		return

	_was_collected = true
	collected.emit()
	GameManager.collect_scarab()
	queue_free()
