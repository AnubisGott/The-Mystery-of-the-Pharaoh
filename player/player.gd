extends CharacterBody3D

@export var move_speed: float = 5.0
@export var mouse_sensitivity: float = 0.0025
@export var yaw_limit_degrees: float = 45.0

@onready var camera_pivot: Node3D = $CameraPivot

var _pitch: float = 0.0
var _yaw: float = 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return

	if get_tree().paused:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var yaw_limit := deg_to_rad(yaw_limit_degrees)
		_yaw = clamp(_yaw - event.relative.x * mouse_sensitivity, -yaw_limit, yaw_limit)
		rotation.y = _yaw
		_pitch = clamp(_pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-60.0), deg_to_rad(30.0))
		camera_pivot.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return

	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (global_transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()

	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed

	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1

	move_and_slide()


func _toggle_pause() -> void:
	var should_pause := not get_tree().paused
	get_tree().paused = should_pause
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if should_pause else Input.MOUSE_MODE_CAPTURED
