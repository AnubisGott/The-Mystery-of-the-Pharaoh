extends CharacterBody3D

signal respawned

@export var move_speed: float = 5.0
@export var sprint_speed: float = 7.5
# Sprinting is disabled outdoors (Level 1) and enabled in the pyramid.
@export var sprint_allowed: bool = true
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
# Levels where falling is routine (the crocodile crossing) turn the
# falling sounds off.
@export var fall_sounds_enabled: bool = true
# While set, the level owns the horizontal velocity (the mobile hops of
# Level 6 fly a ballistic arc). Gravity, collisions and landing stay with
# the player. Never set on desktop.
var external_motion: bool = false
# Widens the sideways step without touching the forward pace. Level 3's
# phone climb dodges with two buttons instead of a keyboard, and needs to
# cross a lane faster than it walks. 1.0 everywhere else.
var strafe_multiplier: float = 1.0

const STAND_HEIGHT: float = 1.8
const DUCK_HEIGHT: float = 1.3
# Fixed pivot height (independent of the body jumping/ducking) so the
# screen-space 2D spears visibly fly straight. Framed around the
# character's torso so the whole body, boots included, stays in view.
const CAMERA_HEIGHT: float = 1.55
# The body dips below this only when dropping into a pit (a jump goes up,
# never below the standing torso), so it cleanly marks the start of a fall.
const FALL_WHISTLE_Y: float = 0.5

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

var _camera_base_y: float = 0.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var visual: Node3D = $Visual
@onready var _anim: AnimationPlayer = $Visual/AnimationPlayer
@onready var _footstep_player: AudioStreamPlayer = $FootstepPlayer
@onready var _hit_player: AudioStreamPlayer = $HitPlayer
# Optional: a distinct cry for falling deaths (present on the Level-2
# player). Falls back to the spear-hit sound where it is absent.
@onready var _fall_player: AudioStreamPlayer = get_node_or_null("FallPlayer")
# Optional: a bomb-drop whistle the instant the player pitches into a pit.
@onready var _whistle_player: AudioStreamPlayer = get_node_or_null("WhistlePlayer")

# The soft touch-down thud after a jump or drop.
const LAND_SOUND: AudioStream = preload("res://sounds/croc_land.wav")
var _land_player: AudioStreamPlayer

var _pitch: float = 0.0
var _yaw: float = 0.0
var _is_ducking: bool = false
var _is_dying: bool = false
var _was_airborne: bool = false
var _whistle_played: bool = false
var _walk_phase: float = 0.0
var _last_step_index: int = 0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The player keeps processing while paused (to handle unpausing), but
	# the model should freeze with the rest of the world.
	visual.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("player")
	_land_player = AudioStreamPlayer.new()
	_land_player.stream = LAND_SOUND
	_land_player.volume_db = -10.0
	add_child(_land_player)
	# All effects live on the Sfx bus (its own volume slider).
	for sound in [_footstep_player, _hit_player, _fall_player, _whistle_player,
			_land_player]:
		if sound != null:
			sound.bus = "Sfx"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	$CameraPivot/CameraArm.add_excluded_object(get_rid())
	visual.position.y = -STAND_HEIGHT / 2.0 + visual_lift
	for clip in LOOPED_CLIPS:
		_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_anim.play("Idle")
	_camera_base_y = _camera_target_y()


func _unhandled_input(event: InputEvent) -> void:
	# ESC/pausing is handled by the level's PauseMenu.
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
		camera_pivot.global_position.y = _camera_base_y
		return

	if Input.is_action_pressed("duck") != _is_ducking:
		_set_ducking(not _is_ducking)

	var speed := move_speed
	if _is_ducking:
		speed = duck_speed
	elif sprint_allowed and Input.is_action_pressed("sprint"):
		speed = sprint_speed
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (global_transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()

	# A hop in flight keeps the velocity the level gave it.
	if not external_motion:
		var move := direction * speed
		if strafe_multiplier != 1.0:
			# Scale only the part of the step that goes sideways.
			var right := global_transform.basis.x
			move += right * right.dot(move) * (strafe_multiplier - 1.0)
		velocity.x = move.x
		velocity.z = move.z

	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1

	if is_on_floor() and not _is_ducking and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
		_anim.speed_scale = 1.0
		_anim.play("Jump_Start", 0.1)

	var was_airborne := not is_on_floor()
	var falling_fast := velocity.y < -2.5
	move_and_slide()
	# Touching down after a jump or drop lands with a soft thud.
	if was_airborne and is_on_floor() and falling_fast:
		_land_player.play()
	# The camera floats at a fixed height above the feet. Following them
	# only while grounded (smoothed) keeps it steady through jumps and
	# ducks, yet lets it climb stairs and slopes with the player.
	if is_on_floor():
		_camera_base_y = lerpf(_camera_base_y, _camera_target_y(), minf(delta * 10.0, 1.0))
	camera_pivot.global_position.y = _camera_base_y
	_update_animation()
	_update_footsteps(delta)
	_check_fall_whistle()


# Feet height plus the camera offset; exact in every duck state because
# _set_ducking shifts the body in the same frame the capsule resizes.
func _camera_target_y() -> float:
	var capsule: CapsuleShape3D = collision_shape.shape
	return global_position.y - capsule.height * 0.5 + CAMERA_HEIGHT


func is_ducking() -> bool:
	return _is_ducking


func is_dying() -> bool:
	return _is_dying


# Hit by a spear: thud, fall over, lie still, then restart. A head-high
# spear slams the body face-down forward (Death_B), one against the feet
# flings it onto the back (Death_A). One tween chain, no awaits: a
# coroutine suspended on a SceneTreeTimer leaks at exit if the game quits
# mid-sequence.
func die_and_reset(spawn: Transform3D, hit_high: bool = true, animate: bool = true,
		hit_sound: bool = true) -> void:
	if _is_dying:
		return

	_is_dying = true
	velocity = Vector3.ZERO

	var tween := create_tween()
	if animate:
		# Hit by a spear/pendulum: the impact sound, then the death clip.
		# The forward slam is longer, play it faster so both deaths restart
		# at a similar pace. The wait derives from the clip length (they
		# differ per character), plus a beat on the ground. Levels with
		# their own impact audio (the slide's bump) silence the cry.
		if hit_sound:
			_hit_player.play()
		var clip := "Death_B" if hit_high else "Death_A"
		var speed := 1.5 if hit_high else 1.0
		_anim.speed_scale = speed
		_anim.play(clip, 0.1)
		tween.tween_interval(clampf(_anim.get_animation(clip).length / speed + 0.35, 0.8, 2.2))
	else:
		# Falling into a pit: the falling/impact cry, keep the airborne
		# flail, then a short beat before respawning. Levels with their
		# own fall audio (the splash) silence it.
		if fall_sounds_enabled:
			(_fall_player if _fall_player else _hit_player).play()
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

	# A hop cut short by death must not leave the level owning the
	# velocity - the respawned player would be unable to move.
	external_motion = false
	global_transform = spawn
	velocity = Vector3.ZERO
	_yaw = 0.0
	_pitch = 0.0
	_whistle_played = false
	camera_pivot.rotation.x = 0.0
	# Teleports must not be smoothed across.
	_camera_base_y = _camera_target_y()
	respawned.emit()


# The instant the body drops below the floor into a pit, sound the
# falling-bomb whistle once; re-armed when the feet are back on solid ground.
func _check_fall_whistle() -> void:
	if _whistle_player == null or not fall_sounds_enabled:
		return
	if is_on_floor():
		_whistle_played = false
	elif not _whistle_played and global_position.y < FALL_WHISTLE_Y:
		_whistle_player.play()
		_whistle_played = true


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


