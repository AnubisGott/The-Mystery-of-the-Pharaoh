extends StaticBody3D

@onready var collision_shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	GameManager.all_scarabs_collected.connect(open_gate)

	if GameManager.gate_is_open:
		open_gate()


func open_gate() -> void:
	visible = false
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	collision_shape.set_deferred("disabled", true)
