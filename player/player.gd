extends CharacterBody3D

signal respawned

@export var move_speed: float = 5.0
@export var sprint_speed: float = 7.5
@export var duck_speed: float = 2.5
@export var jump_velocity: float = 3.8
@export var mouse_sensitivity: float = 0.0025
# Horizontal look limit around the spawn direction; 0 or less means
# free 360-degree rotation (used indoors where the corridor turns).
@export var yaw_limit_degrees: float = 45.0
# Raises the visual model without moving the capsule/camera. Level 1's
# path surface sits 5 cm above the sand collision the capsule rests on,
# so the model needs lifting to stand on the path instead of in it.
@export var visual_lift: float = 0.0

const STAND_HEIGHT: float = 1.8
const DUCK_HEIGHT: float = 1.3
# Keeps the view steady while the body jumps or ducks, so screen-space
# overlays (the 2D spears) visibly fly straight.
const CAMERA_HEIGHT: float = 2.3

# The GLB imports every clip as one-shot; these cycle while they play.
const LOOPED_CLIPS: Array[String] = [
	"Idle", "Walking_A", "Running_A", "Jump_Idle", "Crouch_Idle", "Crouch_Walk",
]
# Ground speed at which each cycle plays at 1x; faster movement speeds the
# clip up proportionally so the stride roughly tracks the floor. Exported
# because each character's clips have their own natural pace (KayKit vs
# the MakeHuman/Quaternius variant).
@export var walk_stride_speed: float = 3.0
@export var run_stride_speed: float = 5.5
@export var crouch_stride_speed: float = 2.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var visual: Node3D = $Visual
@onready var _anim: AnimationPlayer = $Visual/AnimationPlayer
@onready var _footstep_player: AudioStreamPlayer = $FootstepPlayer
@onready var _hit_player: AudioStreamPlayer = $HitPlayer

var _pitch: float = 0.0
var _yaw: float = 0.0
var _is_ducking: bool = false
var _is_dying: bool = false
var _was_airborne: bool = false
var _walk_phase: float = 0.0
var _last_step_index: int = 0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The player keeps processing while paused (to handle unpausing), but
	# the model should freeze with the rest of the world.
	visual.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	$CameraPivot/CameraArm.add_excluded_object(get_rid())
	visual.position.y = -STAND_HEIGHT / 2.0 + visual_lift
	for clip in LOOPED_CLIPS:
		_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_anim.play("Idle")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return

	if get_tree().paused:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_look(event.relative)


func _apply_look(relative: Vector2) -> void:
	if yaw_limit_degrees > 0.0:
		var yaw_limit := deg_to_rad(yaw_limit_degrees)
		_yaw = clamp(_yaw - relative.x * mouse_sensitivity, -yaw_limit, yaw_limit)
	else:
		_yaw = wrapf(_yaw - relative.x * mouse_sensitivity, -PI, PI)
	rotation.y = _yaw
	_pitch = clamp(_pitch - relative.y * mouse_sensitivity, deg_to_rad(-60.0), deg_to_rad(30.0))
	camera_pivot.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return

	if _is_dying:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= _gravity * delta
		move_and_slide()
		camera_pivot.global_position.y = CAMERA_HEIGHT
		return

	if Input.is_action_pressed("duck") != _is_ducking:
		_set_ducking(not _is_ducking)

	var speed := move_speed
	if _is_ducking:
		speed = duck_speed
	elif Input.is_action_pressed("sprint"):
		speed = sprint_speed
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
		_anim.speed_scale = 1.0
		_anim.play("Jump_Start", 0.1)

	move_and_slide()
	camera_pivot.global_position.y = CAMERA_HEIGHT
	_update_animation()
	_update_footsteps(delta)


func is_ducking() -> bool:
	return _is_ducking


func is_dying() -> bool:
	return _is_dying


# Hit by a spear: thud, fall over, lie still, then restart. A head-high
# spear slams the body face-down forward (Death_B), one against the feet
# flings it onto the back (Death_A). One tween chain, no awaits: a
# coroutine suspended on a SceneTreeTimer leaks at exit if the game quits
# mid-sequence.
func die_and_reset(spawn: Transform3D, hit_high: bool = true, animate: bool = true) -> void:
	if _is_dying:
		return

	_is_dying = true
	_hit_player.play()
	velocity = Vector3.ZERO

	var tween := create_tween()
	if animate:
		# The forward slam is longer, play it faster so both deaths
		# restart at a similar pace. The wait derives from the clip
		# length (they differ per character), plus a beat on the ground.
		var clip := "Death_B" if hit_high else "Death_A"
		var speed := 1.5 if hit_high else 1.0
		_anim.speed_scale = speed
		_anim.play(clip, 0.1)
		tween.tween_interval(clampf(_anim.get_animation(clip).length / speed + 0.35, 0.8, 2.2))
	else:
		# Falling into a pit: keep the airborne flail, just a short beat.
		tween.tween_interval(0.4)
	tween.tween_callback(_finish_death.bind(spawn))


func _finish_death(spawn: Transform3D) -> void:
	_anim.speed_scale = 1.0
	_anim.play("Idle")
	reset_to_start(spawn)
	_is_dying = false


func reset_to_start(spawn: Transform3D) -> void:
	if _is_ducking:
		_set_ducking(false)

	global_transform = spawn
	velocity = Vector3.ZERO
	_yaw = 0.0
	_pitch = 0.0
	camera_pivot.rotation.x = 0.0
	respawned.emit()


func _set_ducking(ducking: bool) -> void:
	_is_ducking = ducking
	var capsule: CapsuleShape3D = collision_shape.shape
	capsule.height = DUCK_HEIGHT if ducking else STAND_HEIGHT

	# Shift the body by the height difference in the same frame the
	# capsule resizes, so the feet stay planted and only the head moves.
	# The visual's origin is at the feet: keep it on the capsule bottom.
	# The crouch pose itself comes from the Crouch_* animation clips.
	if ducking:
		visual.position.y = -DUCK_HEIGHT / 2.0 + visual_lift
		position.y -= (STAND_HEIGHT - DUCK_HEIGHT) / 2.0
	else:
		visual.position.y = -STAND_HEIGHT / 2.0 + visual_lift
		position.y += (STAND_HEIGHT - DUCK_HEIGHT) / 2.0


# Picks the clip matching the current movement state. Jump_Start and
# Jump_Land are one-shots that get to finish before the state takes over
# again; everything else follows velocity directly.
func _update_animation() -> void:
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	var airborne := not is_on_floor()
	var just_landed := _was_airborne and not airborne
	_was_airborne = airborne

	var target := "Idle"
	var time_scale := 1.0
	if airborne:
		if _anim.current_animation == "Jump_Start":
			return  # let the takeoff finish, Jump_Idle follows
		target = "Jump_Idle"
	elif _is_ducking and ground_speed > 0.2:
		target = "Crouch_Walk"
		time_scale = ground_speed / crouch_stride_speed
	elif _is_ducking:
		target = "Crouch_Idle"
	elif ground_speed > move_speed + 0.2:
		target = "Running_A"
		time_scale = ground_speed / run_stride_speed
	elif ground_speed > 0.2:
		target = "Walking_A"
		time_scale = ground_speed / walk_stride_speed
	elif just_landed:
		target = "Jump_Land"
	elif _anim.current_animation == "Jump_Land":
		return  # let the landing finish before idling
	_anim.speed_scale = time_scale
	if _anim.current_animation != target:
		_anim.play(target, 0.2)


# One footfall per half stride, paced by ground speed like the old
# procedural walk, so steps stay in sync at every movement speed.
func _update_footsteps(delta: float) -> void:
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	if ground_speed > 0.2 and is_on_floor():
		_walk_phase += delta * ground_speed * 2.2
		var step_index := int(_walk_phase / PI)
		if step_index != _last_step_index:
			_last_step_index = step_index
			_footstep_player.play()
	else:
		_walk_phase = 0.0
		_last_step_index = 0


func _toggle_pause() -> void:
	var should_pause := not get_tree().paused
	get_tree().paused = should_pause
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if should_pause else Input.MOUSE_MODE_CAPTURED
