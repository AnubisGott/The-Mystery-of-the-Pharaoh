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

const LANES: Array[float] = [-1.4, 0.0, 1.4]
const BOULDER_SPEED: float = 7.5
# The spawn interval ramps from easy to relentless with climb progress.
const INTERVAL_EASY: float = 2.8
const INTERVAL_HARD: float = 0.9
const FIRST_BOULDER_DELAY: float = 1.5
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

	if intro_enabled and DisplayServer.get_name() != "headless":
		_play_intro()
	else:
		_boulder_timer.start(FIRST_BOULDER_DELAY)


func _physics_process(_delta: float) -> void:
	# Safety net: below the ramp line means death.
	var lp := to_local(player.global_position)
	if lp.y < _ramp_y(lp.z) - 3.5 and not player.is_dying():
		if GameManager.god_mode:
			player.reset_to_start(_spawn_transform)
		else:
			player.die_and_reset(_spawn_transform, true, false)


func _unhandled_input(event: InputEvent) -> void:
	# Skip the intro on a fresh key or click - but not on key repeats
	# or input left over from finishing the previous level (a short
	# grace period swallows those).
	if _intro_running and _intro_can_skip and event.is_pressed() \
			and not event.is_echo() \
			and (event is InputEventKey or event is InputEventMouseButton):
		_intro_skip = true


# ------------------------------------------------------------ staircase

# Height of the walkable ramp line at local z.
func _ramp_y(z: float) -> float:
	return clampf((STAIRS_START_Z - z) * SLOPE, 0.0, TOP_Y)


func _build_geometry() -> void:
	var pitch := atan(SLOPE)

	# Flat start and top platforms.
	_add_box(Vector3(0, -0.2, 2.25), Vector3(CORRIDOR_WIDTH, 0.4, 8.5), FLOOR_MATERIAL)
	_add_box(Vector3(0, TOP_Y - 0.2, STAIRS_END_Z - 4.0),
			Vector3(CORRIDOR_WIDTH, 0.4, 8.0), FLOOR_MATERIAL)

	# The walkable surface is one invisible ramp through the step noses.
	var normal := Vector3(0, cos(pitch), sin(pitch))
	var ramp_mid := Vector3(0, TOP_Y * 0.5, (STAIRS_START_Z + STAIRS_END_Z) * 0.5)
	var ramp_len := (STAIRS_START_Z - STAIRS_END_Z) / cos(pitch)
	_add_box(ramp_mid - normal * 0.2, Vector3(CORRIDOR_WIDTH, 0.4, ramp_len),
			FLOOR_MATERIAL, pitch, true, false)

	# The visible steps; their top front edges lie on the ramp line.
	var step_mesh := BoxMesh.new()
	step_mesh.size = Vector3(CORRIDOR_WIDTH, STEP_RISE, STEP_RUN)
	step_mesh.material = FLOOR_MATERIAL
	var steps := int((STAIRS_START_Z - STAIRS_END_Z) / STEP_RUN)
	for i in steps:
		var step := MeshInstance3D.new()
		step.mesh = step_mesh
		step.position = Vector3(0, (i + 0.5) * STEP_RISE,
				STAIRS_START_Z - (i + 0.5) * STEP_RUN)
		add_child(step)

	# Walls and ceilings: flat pieces over the platforms, pitched slabs
	# along the stairs (walls reach below the ramp to line the holes).
	var mid_y := TOP_Y * 0.5
	var mid_z := (STAIRS_START_Z + STAIRS_END_Z) * 0.5
	var slope_len := (STAIRS_START_Z - STAIRS_END_Z) / cos(pitch) + 2.0
	for side: float in [-1.0, 1.0]:
		var x: float = side * (CORRIDOR_WIDTH * 0.5 + 0.2)
		_add_box(Vector3(x, 2.8, 2.25), Vector3(0.4, 7.0, 8.5), WALL_MATERIAL)
		_add_box(Vector3(x, mid_y, mid_z) + normal * 0.25,
				Vector3(0.4, WALL_HEIGHT + 4.0, slope_len), WALL_MATERIAL, pitch)
		_add_box(Vector3(x, TOP_Y + 2.8, STAIRS_END_Z - 4.0),
				Vector3(0.4, 7.0, 8.5), WALL_MATERIAL)
	_add_box(Vector3(0, WALL_HEIGHT, 2.25), Vector3(5.2, 0.4, 8.5), WALL_MATERIAL)
	_add_box(Vector3(0, mid_y, mid_z) + normal * WALL_HEIGHT,
			Vector3(5.2, 0.4, slope_len), WALL_MATERIAL, pitch)
	_add_box(Vector3(0, TOP_Y + WALL_HEIGHT, STAIRS_END_Z - 4.0),
			Vector3(5.2, 0.4, 8.5), WALL_MATERIAL)

	# Closing walls: behind the spawn and behind the exit doorway.
	_add_box(Vector3(0, 2.8, 6.7), Vector3(5.2, 7.0, 0.4), WALL_MATERIAL)
	_add_box(Vector3(0, TOP_Y + 2.8, STAIRS_END_Z - 8.2),
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
	doorway.position = Vector3(0, TOP_Y + 1.35, STAIRS_END_Z - 7.9)
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
	exit_sign.position = Vector3(0.95, TOP_Y + 2.4, STAIRS_END_Z - 7.75)
	add_child(exit_sign)


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
	while z > STAIRS_END_Z - 5.0:
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
	return clampf((STAIRS_START_Z - lp.z) / (STAIRS_START_Z - STAIRS_END_Z), 0.0, 1.0)


# Base spawn interval for a given climb progress (jitter comes on top).
func _spawn_interval(progress: float) -> float:
	return lerpf(INTERVAL_EASY, INTERVAL_HARD, progress)


func _on_boulder_timer_timeout() -> void:
	# The final stretch stays boulder-free so the arrival at the top is
	# never cheap-shotted from point-blank range.
	if _progress() < CALM_PROGRESS:
		_spawn_boulder()
	_boulder_timer.start(_spawn_interval(_progress()) * randf_range(0.85, 1.15))


func _spawn_boulder() -> Node3D:
	var boulder: Node3D = Boulder.new()
	boulder.direction = Vector3(0, -SLOPE, 1).normalized()
	boulder.speed = BOULDER_SPEED
	boulder.flatten_z = STAIRS_START_Z
	boulder.despawn_z = 5.5
	var z := maxf(STAIRS_END_Z, to_local(player.global_position).z - SPAWN_AHEAD_Z)
	boulder.position = Vector3(LANES[randi() % LANES.size()],
			_ramp_y(z) + Boulder.RADIUS, z)
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

# A ~4 s cinematic: a boulder bounces down the stairs in slow motion
# while the camera zooms in and back out; mid-shot the frame freezes
# and the level name is stamped on it. Any key or click skips it.
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
	title.setup("Level 3", "Up the Stairs")
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
		boulder.position = Vector3(0, _ramp_y(z) + Boulder.RADIUS, z)
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
