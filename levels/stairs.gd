extends Node3D

# Level 3: Up the Stairs. One long torch-lit staircase inside the
# pyramid. Boulders roll down it in three lanes — rarely at first, then
# more and more often the higher the player climbs. The exit is at
# the top.

const LEVEL_MUSIC: AudioStream = preload("res://soundAndMusic/music/AztekenherausforderungLevel03.mp3")
const WALL_MATERIAL: StandardMaterial3D = preload("res://materials/sandstone_sphinx.tres")
const FLOOR_MATERIAL: StandardMaterial3D = preload("res://materials/sandstone_pyramid.tres")
const Torch := preload("res://levels/torch.gd")
const Boulder := preload("res://hazards/boulder.gd")
const IntroTitle := preload("res://ui/intro_title.gd")
const TouchControls := preload("res://ui/touch_controls.gd")

# How long the intro freezes mid-shot to stamp the level name on the
# frame, at the standard 4 s duration (it scales with the duration).
const INTRO_HOLD: float = 1.4

# The staircase frame: a flat start platform, stairs rising toward -Z,
# and a flat top platform with the exit.
const SLOPE: float = 0.35
const STAIRS_START_Z: float = -2.0
const STAIRS_END_Z: float = -112.0
const STEP_RUN: float = 0.5
const STEP_RISE: float = STEP_RUN * SLOPE
const CORRIDOR_WIDTH: float = 4.4
const WALL_HEIGHT: float = 4.5
const TOP_Y: float = (STAIRS_START_Z - STAIRS_END_Z) * SLOPE
# The pitched shell of the staircase overhangs each flat platform by about
# a meter. Its walls are rotated around X, so their faces stay in exactly
# the planes the platform walls sit in - two coincident surfaces, which the
# phone's depth buffer cannot separate: the wall flickers at the foot and at
# the head of the stairs. The platform walls stand this much further into the
# corridor, so where the two overlap the platform wall is plainly the nearer
# one. (Inward, not outward: outward would open a slit at the floor edge.)
const PLATFORM_WALL_OFFSET: float = 0.06
# The phone climb runs on for another 48 m: the boulders come at a
# gentler pace there (two lanes, no twin waves), so the staircase is the
# longer one. Everything at the top - platform, doorway, exit sign and
# win zone - follows it up.
const STAIRS_END_Z_TOUCH: float = -160.0

const LANES: Array[float] = [-1.4, 0.0, 1.4]
# On a phone the climb is dodged left and right like on the desktop, but
# with two lanes instead of three: one boulder always leaves a free side,
# and the two buttons map cleanly onto them.
const LANES_TOUCH: Array[float] = [-1.3, 1.3]
const BOULDER_SPEED: float = 7.5
# With two lanes the boulders are heftier: half the corridor wide, against
# a third of it on the desktop's three-lane climb.
const BOULDER_RADIUS_TOUCH: float = CORRIDOR_WIDTH / 4.0
# How much quicker the phone climb steps sideways than it walks.
const STRAFE_BOOST_TOUCH: float = 2.2
# The spawn interval ramps from busy to relentless with climb progress.
const INTERVAL_EASY: float = 1.0
const INTERVAL_HARD: float = 0.4
# Thumbs are slower than fingers on a keyboard: the touch ramp tops out
# gentler, and with only two lanes a twin wave would wall the stairs off
# completely, so there is never one.
const INTERVAL_HARD_TOUCH: float = 0.75
# A wave is one boulder, sometimes two — never all three lanes at once,
# so there is always a way through.
const TWIN_CHANCE: float = 0.4
const FIRST_BOULDER_DELAY: float = 0.8
# Boulders spawn this far up-slope from the player (capped at the top),
# so the first ones arrive within seconds instead of rolling the whole
# staircase down first.
const SPAWN_AHEAD_Z: float = 42.0
# Past this progress no fresh boulders spawn: the last stretch to the
# exit stays clear.
const CALM_PROGRESS: float = 0.9

@onready var player: CharacterBody3D = $Player
@onready var god_label: Label = $ControlsHint/Root/GodLabel

# The pre-play cinematic; disabled for headless runs (tests).
@export var intro_enabled: bool = true

var _spawn_transform: Transform3D
var _boulder_timer: Timer
var _intro_running: bool = false
var _intro_skip: bool = false
var _intro_can_skip: bool = false


func _ready() -> void:
	_spawn_transform = player.global_transform
	GameManager.play_music(LEVEL_MUSIC)
	_build_environment()
	_build_geometry()
	_build_torches()

	god_label.visible = GameManager.god_mode
	GameManager.god_mode_changed.connect(_on_god_mode_changed)
	player.respawned.connect(_on_player_respawned)

	_boulder_timer = Timer.new()
	_boulder_timer.one_shot = true
	_boulder_timer.timeout.connect(_on_boulder_timer_timeout)
	add_child(_boulder_timer)

	if GameManager.touch_mode:
		_setup_touch_mode()

	if intro_enabled and DisplayServer.get_name() != "headless":
		_play_intro()
	else:
		_boulder_timer.start(FIRST_BOULDER_DELAY)


# Android port scheme for Level 3: the adventurer climbs on his own and
# the two buttons dodge the boulders left and right - the desktop's
# gameplay, on two lanes.
func _setup_touch_mode() -> void:
	get_node("ControlsHint").visible = false
	# A thumb dodges later than a finger on a key, so the sideways step is
	# the quicker one: the climb keeps its pace, the lane change doubles.
	player.strafe_multiplier = STRAFE_BOOST_TOUCH
	var touch: CanvasLayer = TouchControls.new()
	add_child(touch)
	touch.add_button("<", "move_left", false, 0, 0, touch.BIG_SIDE_RADIUS, true)
	touch.add_button(">", "move_right", true, 0, 0, touch.BIG_SIDE_RADIUS, true)
	touch.add_pause_button()


# The boulders the level rolls: fat two-lane ones on a phone.
func _boulder_radius() -> float:
	return BOULDER_RADIUS_TOUCH if GameManager.touch_mode else Boulder.RADIUS


# Where the staircase tops out, and how high that is.
func _end_z() -> float:
	return STAIRS_END_Z_TOUCH if GameManager.touch_mode else STAIRS_END_Z


func _top_y() -> float:
	return (STAIRS_START_Z - _end_z()) * SLOPE


# The lanes the boulders roll down: three on the desktop, two on a phone.
func _lanes() -> Array:
	return LANES_TOUCH if GameManager.touch_mode else LANES


# Keeps the player climbing straight up the stairs (toward -Z).
func _drive_auto_run(delta: float) -> void:
	if _intro_running or player.is_dying():
		Input.action_release("move_forward")
		return
	player.rotation.y = lerp_angle(player.rotation.y, 0.0, minf(delta * 6.0, 1.0))
	player._yaw = player.rotation.y
	Input.action_press("move_forward")


func _exit_tree() -> void:
	# Auto-run holds move_forward down; do not leak it into other scenes.
	if GameManager.touch_mode:
		Input.action_release("move_forward")


func _physics_process(delta: float) -> void:
	if GameManager.touch_mode:
		_drive_auto_run(delta)

	# Safety net: below the ramp line means death.
	var lp := to_local(player.global_position)
	if lp.y < _ramp_y(lp.z) - 3.5 and not player.is_dying():
		if GameManager.god_mode:
			player.reset_to_start(_spawn_transform)
		else:
			player.die_and_reset(_spawn_transform, true, false)


# ------------------------------------------------------------ staircase

# Height of the walkable ramp line at local z.
func _ramp_y(z: float) -> float:
	return clampf((STAIRS_START_Z - z) * SLOPE, 0.0, _top_y())


func _build_geometry() -> void:
	var pitch := atan(SLOPE)
	var end_z := _end_z()
	var top_y := _top_y()

	# Flat start and top platforms.
	_add_box(Vector3(0, -0.2, 2.25), Vector3(CORRIDOR_WIDTH, 0.4, 8.5), FLOOR_MATERIAL)
	_add_box(Vector3(0, top_y - 0.2, end_z - 4.0),
			Vector3(CORRIDOR_WIDTH, 0.4, 8.0), FLOOR_MATERIAL)

	# The walkable surface is one invisible ramp through the step noses.
	var normal := Vector3(0, cos(pitch), sin(pitch))
	var ramp_mid := Vector3(0, top_y * 0.5, (STAIRS_START_Z + end_z) * 0.5)
	var ramp_len := (STAIRS_START_Z - end_z) / cos(pitch)
	_add_box(ramp_mid - normal * 0.2, Vector3(CORRIDOR_WIDTH, 0.4, ramp_len),
			FLOOR_MATERIAL, pitch, true, false)

	# The visible steps; their top front edges lie on the ramp line.
	var step_mesh := BoxMesh.new()
	step_mesh.size = Vector3(CORRIDOR_WIDTH, STEP_RISE, STEP_RUN)
	step_mesh.material = FLOOR_MATERIAL
	var steps := int((STAIRS_START_Z - end_z) / STEP_RUN)
	for i in steps:
		var step := MeshInstance3D.new()
		step.mesh = step_mesh
		step.position = Vector3(0, (i + 0.5) * STEP_RISE,
				STAIRS_START_Z - (i + 0.5) * STEP_RUN)
		add_child(step)

	# Walls and ceilings: flat pieces over the platforms, pitched slabs
	# along the stairs (walls reach below the ramp to line the holes).
	var mid_y := top_y * 0.5
	var mid_z := (STAIRS_START_Z + end_z) * 0.5
	var slope_len := (STAIRS_START_Z - end_z) / cos(pitch) + 2.0
	for side: float in [-1.0, 1.0]:
		var x: float = side * (CORRIDOR_WIDTH * 0.5 + 0.2)
		var platform_x: float = x - side * PLATFORM_WALL_OFFSET
		_add_box(Vector3(platform_x, 2.8, 2.25), Vector3(0.4, 7.0, 8.5), WALL_MATERIAL)
		_add_box(Vector3(x, mid_y, mid_z) + normal * 0.25,
				Vector3(0.4, WALL_HEIGHT + 4.0, slope_len), WALL_MATERIAL, pitch)
		_add_box(Vector3(platform_x, top_y + 2.8, end_z - 4.0),
				Vector3(0.4, 7.0, 8.5), WALL_MATERIAL)
	_add_box(Vector3(0, WALL_HEIGHT, 2.25), Vector3(5.2, 0.4, 8.5), WALL_MATERIAL)
	_add_box(Vector3(0, mid_y, mid_z) + normal * WALL_HEIGHT,
			Vector3(5.2, 0.4, slope_len), WALL_MATERIAL, pitch)
	_add_box(Vector3(0, top_y + WALL_HEIGHT, end_z - 4.0),
			Vector3(5.2, 0.4, 8.5), WALL_MATERIAL)

	# Closing walls: behind the spawn and behind the exit doorway.
	_add_box(Vector3(0, 2.8, 6.7), Vector3(5.2, 7.0, 0.4), WALL_MATERIAL)
	_add_box(Vector3(0, top_y + 2.8, end_z - 8.2),
			Vector3(5.2, 7.0, 0.4), WALL_MATERIAL)

	# The dark exit doorway and its sign on the top platform.
	var dark := StandardMaterial3D.new()
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.albedo_color = Color(0.02, 0.015, 0.01)
	var doorway := MeshInstance3D.new()
	var doorway_mesh := BoxMesh.new()
	doorway_mesh.size = Vector3(2.6, 2.7, 0.2)
	doorway_mesh.material = dark
	doorway.mesh = doorway_mesh
	doorway.position = Vector3(0, top_y + 1.35, end_z - 7.9)
	add_child(doorway)

	var sign_material := StandardMaterial3D.new()
	sign_material.albedo_color = Color(0.1, 0.85, 0.3)
	sign_material.emission_enabled = true
	sign_material.emission = Color(0.1, 0.85, 0.3)
	sign_material.emission_energy_multiplier = 2.0
	var exit_sign := MeshInstance3D.new()
	var sign_mesh := BoxMesh.new()
	sign_mesh.size = Vector3(0.9, 0.4, 0.12)
	sign_mesh.material = sign_material
	exit_sign.mesh = sign_mesh
	exit_sign.position = Vector3(0.95, top_y + 2.4, end_z - 7.75)
	add_child(exit_sign)

	# The win zone is placed in the scene, at the desktop top; the longer
	# phone climb carries it up to its own doorway.
	if GameManager.touch_mode:
		$WinZone.position = Vector3(0.0, top_y + 1.2, end_z - 6.8)


func _add_box(center: Vector3, size: Vector3, material: Material,
		pitch: float = 0.0, with_collision: bool = true, visual: bool = true) -> void:
	var parent: Node3D
	if with_collision:
		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
		parent = body
	else:
		parent = Node3D.new()
	if visual:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		box.material = material
		mesh.mesh = box
		parent.add_child(mesh)
	parent.position = center
	parent.rotation.x = pitch
	add_child(parent)


func _build_torches() -> void:
	# From the start platform up past the exit platform, alternating.
	var side := 1.0
	var z := 2.0
	while z > _end_z() - 5.0:
		var torch := Torch.new()
		torch.basis = Basis.looking_at(Vector3(-side, 0, 0))
		torch.position = Vector3(side * (CORRIDOR_WIDTH * 0.5 - 0.05),
				_ramp_y(z) + 2.35, z)
		add_child(torch)
		side = -side
		z -= 10.0


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
	env.fog_density = 0.03
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


# ------------------------------------------------------------- boulders

# How far up the player has climbed, 0 at the bottom to 1 at the top.
func _progress() -> float:
	var lp := to_local(player.global_position)
	return clampf((STAIRS_START_Z - lp.z) / (STAIRS_START_Z - _end_z()), 0.0, 1.0)


# Base spawn interval for a given climb progress (jitter comes on top).
func _spawn_interval(progress: float) -> float:
	var hard := INTERVAL_HARD_TOUCH if GameManager.touch_mode else INTERVAL_HARD
	return lerpf(INTERVAL_EASY, hard, progress)


func _on_boulder_timer_timeout() -> void:
	# The final stretch stays boulder-free so the arrival at the top is
	# never cheap-shotted from point-blank range.
	if _progress() < CALM_PROGRESS:
		# One boulder, sometimes a twin in a DIFFERENT lane: a wave can
		# never wall off all three lanes. On a phone there are only two
		# lanes, so a wave is always a single boulder.
		var lanes := _lanes()
		var lane := randi() % lanes.size()
		_spawn_boulder(lane)
		if not GameManager.touch_mode and randf() < TWIN_CHANCE:
			_spawn_boulder((lane + 1 + randi() % 2) % lanes.size())
	_boulder_timer.start(_spawn_interval(_progress()) * randf_range(0.85, 1.15))


func _spawn_boulder(lane: int = -1) -> Node3D:
	var lanes := _lanes()
	if lane < 0 or lane >= lanes.size():
		lane = randi() % lanes.size()
	var boulder: Node3D = Boulder.new()
	boulder.direction = Vector3(0, -SLOPE, 1).normalized()
	boulder.speed = BOULDER_SPEED
	boulder.radius = _boulder_radius()
	boulder.flatten_z = STAIRS_START_Z
	boulder.despawn_z = 5.5
	var z := maxf(_end_z(), to_local(player.global_position).z - SPAWN_AHEAD_Z)
	boulder.position = Vector3(lanes[lane], _ramp_y(z) + boulder.radius, z)
	add_child(boulder)
	boulder.player_hit.connect(_on_boulder_hit)
	return boulder


func _on_boulder_hit() -> void:
	if GameManager.god_mode or player.is_dying():
		return
	player.die_and_reset(_spawn_transform, false)


func _on_player_respawned() -> void:
	# A fresh attempt: clear the field and ease the pressure back off.
	for boulder in get_tree().get_nodes_in_group("boulders"):
		boulder.queue_free()
	_boulder_timer.start(FIRST_BOULDER_DELAY)


func _on_god_mode_changed(enabled: bool) -> void:
	god_label.visible = enabled


# ---------------------------------------------------------------- intro

func _unhandled_input(event: InputEvent) -> void:
	# Esc skips the intro - a fresh press only, ignoring key repeats
	# and input left over from the previous level (grace period).
	if _intro_running and _intro_can_skip and event is InputEventKey \
			and event.is_pressed() and not event.is_echo() \
			and event.physical_keycode == KEY_ESCAPE:
		_intro_skip = true


# A ~4 s cinematic: a boulder bounces down the stairs in slow motion
# while the camera zooms in and back out; mid-shot the frame freezes
# and the level name is stamped on it. Esc skips it.
func _play_intro(duration: float = 4.0) -> void:
	_intro_running = true
	_intro_skip = false
	_intro_can_skip = false
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	var pause_menu: Node = get_node_or_null("PauseMenu")
	if pause_menu:
		pause_menu.set_process_unhandled_input(false)

	var boulder := _spawn_boulder()
	boulder.set_physics_process(false)
	var cam := Camera3D.new()
	add_child(cam)
	var title := IntroTitle.new()
	title.setup(tr("Level %d") % 3, tr("Up the Stairs"))
	title.visible = false
	add_child(title)

	var hold := INTRO_HOLD * duration / 4.0
	var tree := get_tree()
	var elapsed := 0.0
	var held := 0.0
	while elapsed < duration and not _intro_skip:
		# The level can be torn down mid-intro (scene change); bail out.
		if not is_inside_tree():
			return
		_intro_can_skip = elapsed > 0.6
		var t := elapsed / duration
		# The boulder rolls a short stretch in slow motion.
		var z := lerpf(-38.0, -27.0, t)
		boulder.position = Vector3(0, _ramp_y(z) + boulder.radius, z)
		(boulder.get_child(0) as Node3D).rotation.x = z * 2.0
		# One smooth zoom in and back out over the whole sequence.
		cam.fov = 66.0 - 22.0 * sin(PI * t)
		var cam_z := z + 7.5 - 1.5 * sin(PI * t)
		cam.global_position = to_global(Vector3(1.5, _ramp_y(cam_z) + 1.7, cam_z))
		cam.look_at(to_global(boulder.position), Vector3.UP)
		cam.make_current()
		await tree.process_frame
		var dt := get_process_delta_time()
		# Freeze the frame mid-shot and stamp the level name on it.
		if t >= 0.5 and held < hold:
			held += dt
			title.visible = true
			title.set_opacity(minf(held / 0.25, 1.0))
		else:
			title.visible = false
			elapsed += dt

	title.queue_free()
	boulder.queue_free()
	var player_cam: Camera3D = player.get_node("CameraPivot/CameraArm/Camera3D")
	player_cam.make_current()
	cam.queue_free()
	if pause_menu:
		pause_menu.set_process_unhandled_input(true)
	player.set_process_unhandled_input(true)
	player.set_physics_process(true)
	_intro_running = false
	_boulder_timer.start(FIRST_BOULDER_DELAY)
