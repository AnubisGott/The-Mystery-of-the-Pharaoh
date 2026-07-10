extends StaticBody3D

# A floor tile that cracks and falls shortly after being stepped on:
# 0.0 s step -> 0.6 s crack sound and darkening -> 1.0 s wobble ->
# 1.4 s fall. Respawns a few seconds later. One tween chain, no awaits.
const TILE_SIZE: float = 2.1
const THICKNESS: float = 0.4
const RESPAWN_DELAY: float = 3.0

var _material: StandardMaterial3D
var _mesh: MeshInstance3D
var _collision: CollisionShape3D
var _crack_player: AudioStreamPlayer3D
var _armed: bool = true
var _rest_position: Vector3


func _ready() -> void:
	add_to_group("crack_tiles")
	_rest_position = position

	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.62, 0.5, 0.36)
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(TILE_SIZE - 0.08, THICKNESS, TILE_SIZE - 0.08)
	box.material = _material
	_mesh.mesh = box
	add_child(_mesh)

	_collision = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(TILE_SIZE, THICKNESS, TILE_SIZE)
	_collision.shape = shape
	add_child(_collision)

	var trigger := Area3D.new()
	var trigger_shape := CollisionShape3D.new()
	var trigger_box := BoxShape3D.new()
	trigger_box.size = Vector3(TILE_SIZE, 0.4, TILE_SIZE)
	trigger_shape.shape = trigger_box
	trigger.add_child(trigger_shape)
	trigger.position = Vector3(0.0, THICKNESS / 2.0 + 0.2, 0.0)
	add_child(trigger)
	trigger.body_entered.connect(_on_body_entered)

	_crack_player = AudioStreamPlayer3D.new()
	_crack_player.stream = preload("res://sounds/footstep_sand_1.wav")
	_crack_player.pitch_scale = 0.55
	_crack_player.volume_db = 2.0
	_crack_player.max_distance = 20.0
	add_child(_crack_player)


func _on_body_entered(body: Node3D) -> void:
	if _armed and body.is_in_group("player"):
		_trigger()


func _trigger() -> void:
	_armed = false
	var tween := create_tween()
	tween.tween_interval(0.6)
	tween.tween_callback(_crack)
	tween.tween_interval(0.4)
	tween.tween_callback(_wobble)
	tween.tween_interval(0.4)
	tween.tween_callback(_fall)
	tween.tween_property(self, "position:y", _rest_position.y - 6.0, 0.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_interval(RESPAWN_DELAY)
	tween.tween_callback(_respawn)


func _crack() -> void:
	_crack_player.play()
	_material.albedo_color = Color(0.45, 0.35, 0.24)


func _wobble() -> void:
	rotation.z = 0.05
	_material.albedo_color = Color(0.36, 0.27, 0.18)


func _fall() -> void:
	_collision.set_deferred("disabled", true)


func _respawn() -> void:
	position = _rest_position
	rotation.z = 0.0
	_collision.set_deferred("disabled", false)
	_material.albedo_color = Color(0.62, 0.5, 0.36)
	_armed = true
