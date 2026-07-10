extends CharacterBody3D

@export var move_speed: float = 5.0
@export var duck_speed: float = 2.5
@export var jump_velocity: float = 4.8
@export var mouse_sensitivity: float = 0.0025
@export var yaw_limit_degrees: float = 45.0

const STAND_HEIGHT: float = 1.8
const DUCK_HEIGHT: float = 1.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var visual: Node3D = $Visual

var _pitch: float = 0.0
var _yaw: float = 0.0
var _is_ducking: bool = false
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

	if Input.is_action_pressed("duck") != _is_ducking:
		_set_ducking(not _is_ducking)

	var speed := duck_speed if _is_ducking else move_speed
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (global_transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()

	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1

	if is_on_floor() and not _is_ducking and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	move_and_slide()


func is_ducking() -> bool:
	return _is_ducking


func reset_to_start(spawn: Transform3D) -> void:
	if _is_ducking:
		_set_ducking(false)

	global_transform = spawn
	velocity = Vector3.ZERO
	_yaw = 0.0
	_pitch = 0.0
	camera_pivot.rotation.x = 0.0


func _set_ducking(ducking: bool) -> void:
	_is_ducking = ducking
	var capsule: CapsuleShape3D = collision_shape.shape
	capsule.height = DUCK_HEIGHT if ducking else STAND_HEIGHT

	if ducking:
		visual.scale.y = DUCK_HEIGHT / STAND_HEIGHT
	else:
		visual.scale.y = 1.0
		position.y += (STAND_HEIGHT - DUCK_HEIGHT) / 2.0


func _toggle_pause() -> void:
	var should_pause := not get_tree().paused
	get_tree().paused = should_pause
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if should_pause else Input.MOUSE_MODE_CAPTURED
