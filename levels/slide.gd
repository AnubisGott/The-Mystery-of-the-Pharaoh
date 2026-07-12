extends Node3D

# Level 5: The Slide. After the burial-chamber floor opened, the player
# shoots down a long chute inside the pyramid. The slide is automatic;
# A/D steer left and right around stone blocks, Space jumps the holes.
# At the bottom the chute launches the player into the water.

const LEVEL_MUSIC: AudioStream = preload("res://soundAndMusic/music/AztekenherausforderungLevel05.mp3")
const GLIDE_SOUND: AudioStreamWAV = preload("res://sounds/slide_glide.wav")
const BUMP_SOUND: AudioStream = preload("res://sounds/bump.wav")
const WALL_MATERIAL: StandardMaterial3D = preload("res://materials/sandstone_sphinx.tres")
const FLOOR_MATERIAL: StandardMaterial3D = preload("res://materials/sandstone_pyramid.tres")
const Torch := preload("res://levels/torch.gd")
const IntroTitle := preload("res://ui/intro_title.gd")

const INTRO_HOLD: float = 1.4

# The chute: a smooth ramp dropping toward -Z into a water cavern.
const SLOPE_TAN: float = 0.55
const SLIDE_START_Z: float = 0.0
const SLIDE_END_Z: float = -110.0
const END_Y: float = SLIDE_END_Z * SLOPE_TAN   # -60.5
const CORRIDOR_WIDTH: float = 4.4
const WALL_HEIGHT: float = 4.5
const WATER_Y: float = -70.0

# Holes in the chute (upper edge z, HOLE_LEN long) and stone blocks.
const HOLES: Array[float] = [-30.0, -55.0, -80.0]
const HOLE_LEN: float = 3.0
const OBSTACLES: Array[Vector2] = [
	Vector2(-0.9, -16.0), Vector2(0.9, -20.0), Vector2(1.4, -24.0),
	Vector2(-1.2, -38.0), Vector2(-0.4, -43.0), Vector2(0.0, -47.0),
	Vector2(0.9, -52.0), Vector2(-1.2, -63.0), Vector2(0.2, -67.0),
	Vector2(1.4, -71.0), Vector2(-0.8, -85.0), Vector2(0.0, -88.0),
	Vector2(-1.4, -95.0), Vector2(0.6, -98.5), Vector2(1.2, -102.0),
]

const SPEED_START: float = 8.0
const SPEED_END: float = 12.5
const STEER_SPEED: float = 4.5
# The chute drops away beneath a jump (~5.8 m/s at full speed), which
# turns even small hops into huge flights. A tiny impulse plus heavy
# slide gravity keeps the hop low (~1 m over the chute) and short.
const JUMP_VELOCITY: float = 2.0
const SLIDE_GRAVITY: float = 30.0

@onready var player: CharacterBody3D = $Player
@onready var god_label: Label = $ControlsHint/Root/GodLabel

# The pre-play cinematic; disabled for headless runs (tests).
@export var intro_enabled: bool = true

var _spawn_transform: Transform3D
var _glide_player: AudioStreamPlayer
var _bump_player: AudioStreamPlayer
var _sliding: bool = false
var _intro_running: bool = false
var _intro_skip: bool = false
var _intro_can_skip: bool = false


func _ready() -> void:
	_spawn_transform = player.global_transform
	GameManager.play_music(LEVEL_MUSIC)
	_build_environment()
	_build_geometry()

	god_label.visible = GameManager.god_mode
	GameManager.god_mode_changed.connect(_on_god_mode_changed)

	# The slide drives the body itself; the player only reads the mouse.
	# The pose is the crouch from the first frame on, and again after
	# every respawn (die_and_reset ends on "Idle").
	player.set_physics_process(false)
	player.get_node("Visual/AnimationPlayer").play("Crouch_Idle")
	player.respawned.connect(_on_player_respawned)

	# The gliding loop, audible only while the player rides the chute.
	var glide: AudioStreamWAV = GLIDE_SOUND
	glide.loop_mode = AudioStreamWAV.LOOP_FORWARD
	glide.loop_end = glide.data.size() / 2   # 16-bit mono frames
	_glide_player = AudioStreamPlayer.new()
	_glide_player.stream = glide
	_glide_player.volume_db = -17.0
	_glide_player.bus = "Sfx"
	add_child(_glide_player)

	# The dull blow of slamming into a stone block.
	_bump_player = AudioStreamPlayer.new()
	_bump_player.stream = BUMP_SOUND
	_bump_player.bus = "Sfx"
	add_child(_bump_player)

	if intro_enabled and DisplayServer.get_name() != "headless":
		_play_intro()
	else:
		_sliding = true


func _physics_process(delta: float) -> void:
	if _intro_running or not _sliding or player.is_dying():
		if _glide_player.playing:
			_glide_player.stop()
		return

	var lp := to_local(player.global_position)
	# Fell into a hole (only while still over the chute; past its end
	# the drop into the water is the intended exit). No whistle on the
	# way down — just the landing thud at the bottom.
	if lp.z > SLIDE_END_Z + 2.0 and lp.y < _ramp_y(lp.z) - 5.0:
		player._land_player.play()
		if GameManager.god_mode:
			player.reset_to_start(_spawn_transform)
		else:
			player.die_and_reset(_spawn_transform, true, false)
		return

	var v := player.velocity
	v.x = Input.get_axis("move_left", "move_right") * STEER_SPEED
	var speed := lerpf(SPEED_START, SPEED_END, _progress(lp.z))
	var downhill := Vector3(0, -SLOPE_TAN, -1.0).normalized()
	v.z = downhill.z * speed
	if player.is_on_floor():
		v.y = downhill.y * speed
		if Input.is_action_pressed("jump"):
			v.y = JUMP_VELOCITY
	else:
		v.y -= SLIDE_GRAVITY * delta
	player.velocity = v
	player.move_and_slide()

	# The glide sound follows ground contact: silent from the moment a
	# jump (or a hole) takes the player off the chute until touchdown.
	if player.is_on_floor():
		_glide_player.pitch_scale = lerpf(0.9, 1.15, _progress(lp.z))
		if not _glide_player.playing:
			_glide_player.play()
	elif _glide_player.playing:
		_glide_player.stop()

	# The camera rides the chute line rather than the jump arc: freezing
	# it while airborne (the flat-level rule) let long forward jumps
	# carry it into the ceiling as the chute dropped away beneath.
	var chute_head: float = to_global(Vector3(0, _ramp_y(lp.z), lp.z)).y + 1.55
	player._camera_base_y = lerpf(player._camera_base_y, chute_head, minf(delta * 10.0, 1.0))
	player.camera_pivot.global_position.y = player._camera_base_y


func _on_player_respawned() -> void:
	player.get_node("Visual/AnimationPlayer").play("Crouch_Idle", 0.1)


func _unhandled_input(event: InputEvent) -> void:
	# Skip the intro on a fresh key or click - but not on key repeats
	# or input left over from finishing the previous level (a short
	# grace period swallows those).
	if _intro_running and _intro_can_skip and event.is_pressed() \
			and not event.is_echo() \
			and (event is InputEventKey or event is InputEventMouseButton):
		_intro_skip = true


func _progress(z: float) -> float:
	return clampf((SLIDE_START_Z - z) / (SLIDE_START_Z - SLIDE_END_Z), 0.0, 1.0)


func _ramp_y(z: float) -> float:
	return clampf(SLOPE_TAN * z, END_Y, 0.0)


# ------------------------------------------------------------- geometry

func _build_geometry() -> void:
	var pitch := -atan(SLOPE_TAN)
	var normal := Vector3(0, cos(pitch), sin(pitch))

	# Start platform under the pit the player fell through.
	_add_box(Vector3(0, -0.2, 2.25), Vector3(CORRIDOR_WIDTH, 0.4, 4.5), FLOOR_MATERIAL)
	_add_box(Vector3(0, 2.1, 4.4), Vector3(5.2, 5.0, 0.4), WALL_MATERIAL)

	# The chute surface, split around the holes.
	var edges: Array[float] = [SLIDE_START_Z]
	for hole in HOLES:
		edges.append(hole)
		edges.append(hole - HOLE_LEN)
	edges.append(SLIDE_END_Z)
	for i in range(0, edges.size(), 2):
		var z_a: float = edges[i]
		var z_b: float = edges[i + 1]
		var mid := Vector3(0, (_ramp_y(z_a) + _ramp_y(z_b)) * 0.5, (z_a + z_b) * 0.5)
		var length := (z_a - z_b) / cos(pitch)
		_add_box(mid - normal * 0.25, Vector3(CORRIDOR_WIDTH, 0.5, length),
				FLOOR_MATERIAL, pitch)

	# Walls and ceiling along the chute.
	var mid_y := END_Y * 0.5
	var mid_z := (SLIDE_START_Z + SLIDE_END_Z) * 0.5
	var slope_len := (SLIDE_START_Z - SLIDE_END_Z) / cos(pitch) + 2.0
	for side: float in [-1.0, 1.0]:
		var x: float = side * (CORRIDOR_WIDTH * 0.5 + 0.2)
		_add_box(Vector3(x, mid_y, mid_z) + normal * 0.25,
				Vector3(0.4, WALL_HEIGHT + 6.0, slope_len), WALL_MATERIAL, pitch)
	_add_box(Vector3(0, mid_y, mid_z) + normal * WALL_HEIGHT,
			Vector3(5.2, 0.4, slope_len), WALL_MATERIAL, pitch)

	# Stone blocks to steer around; a brushing hit is deadly.
	for data in OBSTACLES:
		var block := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.1, 1.1, 1.1)
		collision.shape = shape
		block.add_child(collision)
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.1, 1.1, 1.1)
		box.material = WALL_MATERIAL
		mesh.mesh = box
		block.add_child(mesh)
		block.position = Vector3(data.x, _ramp_y(data.y) + 0.4, data.y)
		block.rotation.x = pitch
		add_child(block)

		var area := Area3D.new()
		var area_shape := CollisionShape3D.new()
		var area_box := BoxShape3D.new()
		area_box.size = Vector3(1.25, 1.25, 1.25)
		area_shape.shape = area_box
		area.add_child(area_shape)
		block.add_child(area)
		area.body_entered.connect(_on_obstacle_hit)

	# Torches down the shaft.
	var side := 1.0
	var z := -6.0
	while z > SLIDE_END_Z + 4.0:
		var torch := Torch.new()
		torch.basis = Basis.looking_at(Vector3(-side, 0, 0))
		torch.position = Vector3(side * (CORRIDOR_WIDTH * 0.5 - 0.05),
				_ramp_y(z) + 2.5, z)
		add_child(torch)
		side = -side
		z -= 12.0

	# The water cavern at the bottom.
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.1, 0.35, 0.5, 0.85)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.emission_enabled = true
	water.emission = Color(0.05, 0.25, 0.4)
	water.emission_energy_multiplier = 0.6
	water.roughness = 0.15
	var pool := MeshInstance3D.new()
	var pool_mesh := BoxMesh.new()
	pool_mesh.size = Vector3(26, 0.5, 30)
	pool_mesh.material = water
	pool.mesh = pool_mesh
	pool.position = Vector3(0, WATER_Y - 0.25, -123.0)
	add_child(pool)

	var glow := OmniLight3D.new()
	glow.light_color = Color(0.3, 0.7, 0.9)
	glow.light_energy = 1.4
	glow.omni_range = 22.0
	glow.position = Vector3(0, WATER_Y + 4.0, -120.0)
	add_child(glow)


func _add_box(center: Vector3, size: Vector3, material: Material,
		pitch: float = 0.0) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	mesh.mesh = box
	body.add_child(mesh)
	body.position = center
	body.rotation.x = pitch
	add_child(body)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.01, 0.008)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.4, 0.3)
	env.ambient_light_energy = 0.25
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.045, 0.03)
	env.fog_density = 0.025
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _on_obstacle_hit(body: Node3D) -> void:
	if not body.is_in_group("player") or GameManager.god_mode or player.is_dying():
		return
	# The bump replaces the spear-hit cry.
	_bump_player.play()
	player.die_and_reset(_spawn_transform, true, true, false)


func _on_god_mode_changed(enabled: bool) -> void:
	god_label.visible = enabled


# ---------------------------------------------------------------- intro

# A ~4 s cinematic: the camera hangs over the chute looking down into
# the depth, zooming in and back out; mid-shot the frame freezes for
# the level title. Any key or click skips it.
func _play_intro(duration: float = 4.0) -> void:
	_intro_running = true
	_intro_skip = false
	_intro_can_skip = false
	player.set_process_unhandled_input(false)
	var pause_menu: Node = get_node_or_null("PauseMenu")
	if pause_menu:
		pause_menu.set_process_unhandled_input(false)

	var cam := Camera3D.new()
	add_child(cam)
	var title := IntroTitle.new()
	title.setup("Level 5", "The Slide")
	title.visible = false
	add_child(title)

	var hold := INTRO_HOLD * duration / 4.0
	var tree := get_tree()
	var elapsed := 0.0
	var held := 0.0
	while elapsed < duration and not _intro_skip:
		if not is_inside_tree():
			return
		_intro_can_skip = elapsed > 0.6
		var t := elapsed / duration
		cam.fov = 68.0 - 24.0 * sin(PI * t)
		var cam_z := -2.0 - 6.0 * t
		cam.global_position = to_global(Vector3(
				1.6 - 1.2 * t, _ramp_y(cam_z) + 2.2, cam_z))
		cam.look_at(to_global(Vector3(0, _ramp_y(cam_z - 16.0), cam_z - 16.0)), Vector3.UP)
		cam.make_current()
		await tree.process_frame
		var dt := get_process_delta_time()
		if t >= 0.5 and held < hold:
			held += dt
			title.visible = true
			title.set_opacity(minf(held / 0.25, 1.0))
		else:
			title.visible = false
			elapsed += dt

	title.queue_free()
	var player_cam: Camera3D = player.get_node("CameraPivot/CameraArm/Camera3D")
	player_cam.make_current()
	cam.queue_free()
	if pause_menu:
		pause_menu.set_process_unhandled_input(true)
	player.set_process_unhandled_input(true)
	_intro_running = false
	_sliding = true
