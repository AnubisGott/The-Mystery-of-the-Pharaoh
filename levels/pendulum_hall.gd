extends Node3D

# Level 2: The Pendulum's Journey. A torch-lit hall inside the pyramid
# with two 90-degree turns, built from a section table measured in
# distance d along the corridor centerline. Pendulums swing into
# recessed wall pockets; the gaps between floor segments are the jump
# holes and crumble fields.
const LEVEL_MUSIC: AudioStream = preload("res://soundAndMusic/music/AztekenherausforderungLevel02.mp3")
const AMBIENT_PAD: AudioStream = preload("res://soundAndMusic/sounds/Pad-Sound.mp3")
const WALL_MATERIAL: StandardMaterial3D = preload("res://materials/sandstone_sphinx.tres")
const FLOOR_MATERIAL: StandardMaterial3D = preload("res://materials/sandstone_pyramid.tres")
const PendulumScript := preload("res://hazards/pendulum.gd")
const CrackTileScript := preload("res://hazards/crack_tile.gd")

const CORRIDOR_WIDTH: float = 4.4
const WALL_V: float = 2.4
const CEILING_Y: float = 4.5
const KILL_Y: float = -6.0
const SLOT_HALF: float = 0.7

# The corridor: intro leg, then three turns (left, left, right).
const LEGS := [
	{"origin": Vector3(0, 0, 6), "dir": Vector3(0, 0, -1), "yaw": 0.0},
	{"origin": Vector3(0, 0, -31), "dir": Vector3(-1, 0, 0), "yaw": PI / 2.0},
	{"origin": Vector3(-50, 0, -31), "dir": Vector3(0, 0, 1), "yaw": PI},
	{"origin": Vector3(-50, 0, -4), "dir": Vector3(-1, 0, 0), "yaw": PI / 2.0},
]
const CORNER_DS := [37.0, 87.0, 114.0]

# Solid floor as (d_from, d_to); the gaps are holes and crumble fields.
const FLOOR_D_SEGMENTS := [
	[0.0, 12.0],    # intro: first normal stretch
	[15.0, 23.0],   # after hole 1
	[33.0, 81.0],   # landing after the intro gauntlet, corner 1, the
					# pendulum sections and the S3 jump hole approach
	[84.0, 91.0],   # after the S3 hole, through corner 2
	[95.0, 97.0],   # safe strip inside crumble field (S4)
	[99.0, 103.0],  # after S4
	[107.0, 109.0], # safe strip inside S5
	[111.0, 118.0], # S6 approach, through corner 3
	[122.0, 128.0], # S6 middle platform
	[132.0, 141.0], # landing and chamber entrance
]
# The intro gauntlet: hole 2 (d 23-26), crumbling tiles (26-30),
# hole 3 (30-33) with no solid ground between them.
const CRACK_D_ROWS := [27.0, 29.0, 92.0, 94.0, 98.0, 104.0, 106.0, 110.0, 119.0, 121.0]
# Pendulums as (d, phase offset), phase-locked to a shared clock.
const PENDULUM_DS := [
	[55.0, 0.0],
	[67.0, 0.0],
	[73.0, PI],
	[106.0, 0.0],
	[116.0, 0.9],
	[127.0, PI * 0.6],
]

@onready var player: CharacterBody3D = $Player
@onready var god_label: Label = $ControlsHint/Root/GodLabel

var _spawn_transform: Transform3D


func _ready() -> void:
	_spawn_transform = player.global_transform
	GameManager.play_music(LEVEL_MUSIC)
	_start_ambient_pad()
	_build_environment()
	_build_geometry()
	_build_hazards()

	god_label.visible = GameManager.god_mode
	GameManager.god_mode_changed.connect(_on_god_mode_changed)


func _physics_process(_delta: float) -> void:
	if player.global_position.y < KILL_Y and not player.is_dying():
		if GameManager.god_mode:
			player.reset_to_start(_spawn_transform)
		else:
			player.die_and_reset(_spawn_transform, true, false)


func _on_god_mode_changed(enabled: bool) -> void:
	god_label.visible = enabled


func _on_trap_hit() -> void:
	if GameManager.god_mode:
		return
	player.die_and_reset(_spawn_transform, true)


# ------------------------------------------------------- corridor frames

func _leg_for(d: float) -> int:
	if d <= CORNER_DS[0]:
		return 0
	if d <= CORNER_DS[1]:
		return 1
	return 2


func _leg_u(d: float, leg: int) -> float:
	return d if leg == 0 else d - CORNER_DS[leg - 1]


func _right(leg: int) -> Vector3:
	return (LEGS[leg]["dir"] as Vector3).cross(Vector3.UP)


func _pos(leg: int, u: float, v: float, y: float) -> Vector3:
	return (LEGS[leg]["origin"] as Vector3) + (LEGS[leg]["dir"] as Vector3) * u \
			+ _right(leg) * v + Vector3.UP * y


# Places a box aligned to a leg: size is (across, height, along).
func _leg_box(leg: int, u: float, v: float, y: float, size_v: float, size_y: float,
		size_u: float, material: Material, with_collision: bool = true) -> void:
	var parent: Node3D
	if with_collision:
		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(size_v, size_y, size_u)
		collision.shape = shape
		body.add_child(collision)
		parent = body
	else:
		parent = Node3D.new()
	parent.position = _pos(leg, u, v, y)
	parent.rotation.y = LEGS[leg]["yaw"]
	add_child(parent)

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size_v, size_y, size_u)
	box.material = material
	mesh.mesh = box
	parent.add_child(mesh)


# ------------------------------------------------------------- building

func _build_geometry() -> void:
	for segment in FLOOR_D_SEGMENTS:
		for piece in _split_at_corners(segment[0], segment[1]):
			var leg := _leg_for((piece[0] + piece[1]) / 2.0)
			var u_a := _leg_u(piece[0], leg)
			var u_b := _leg_u(piece[1], leg)
			_leg_box(leg, (u_a + u_b) / 2.0, 0.0, -0.2,
					CORRIDOR_WIDTH, 0.4, u_b - u_a, FLOOR_MATERIAL)

	# Corner slabs (all turns sit on safe floor by design).
	for corner_leg in [1, 2, 3]:
		_leg_box(corner_leg, 0.0, 0.0, -0.2, CORRIDOR_WIDTH, 0.4, CORRIDOR_WIDTH, FLOOR_MATERIAL)

	# Walls per leg and side, with pockets cut out around pendulums. The
	# u-ranges close the outer corner and leave the inner corner open.
	_build_wall(0, WALL_V, -0.2, 39.4)
	_build_wall(0, -WALL_V, -0.2, 34.8)
	_build_wall(1, WALL_V, -2.6, 52.4)
	_build_wall(1, -WALL_V, 2.0, 47.8)
	_build_wall(2, WALL_V, -2.6, 24.8)
	_build_wall(2, -WALL_V, 2.0, 29.4)
	_build_wall(3, WALL_V, 2.0, 27.4)
	_build_wall(3, -WALL_V, -2.6, 27.4)

	# Back wall, end wall, ceilings.
	_leg_box(0, -0.4, 0.0, CEILING_Y / 2.0, CORRIDOR_WIDTH + 0.8, CEILING_Y + 1.0, 0.4, WALL_MATERIAL)
	_leg_box(3, 27.6, 0.0, CEILING_Y / 2.0, CORRIDOR_WIDTH + 0.8, CEILING_Y + 1.0, 0.4, WALL_MATERIAL)
	_leg_box(0, 19.6, 0.0, CEILING_Y + 0.2, CORRIDOR_WIDTH + 0.8, 0.4, 40.4, WALL_MATERIAL)
	_leg_box(1, 24.9, 0.0, CEILING_Y + 0.2, CORRIDOR_WIDTH + 0.8, 0.4, 55.4, WALL_MATERIAL)
	_leg_box(2, 13.6, 0.0, CEILING_Y + 0.2, CORRIDOR_WIDTH + 0.8, 0.4, 32.4, WALL_MATERIAL)
	_leg_box(3, 12.6, 0.0, CEILING_Y + 0.2, CORRIDOR_WIDTH + 0.8, 0.4, 30.4, WALL_MATERIAL)

	# Dark chamber opening with the exit marker at the end of the last leg.
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.02, 0.015, 0.01)
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_leg_box(3, 27.3, 0.0, 1.4, 3.0, 2.8, 0.2, dark, false)

	var sign_material := StandardMaterial3D.new()
	sign_material.albedo_color = Color(0.1, 0.85, 0.3)
	sign_material.emission_enabled = true
	sign_material.emission = Color(0.1, 0.85, 0.3)
	sign_material.emission_energy_multiplier = 2.0
	_leg_box(3, 27.15, 0.95, 2.4, 0.9, 0.4, 0.12, sign_material, false)


func _split_at_corners(a: float, b: float) -> Array:
	var pieces: Array = []
	var bounds := [a, b]
	var starts := [a]
	for corner in CORNER_DS:
		if corner > a and corner < b:
			starts.append(corner)
	starts.append(b)
	for i in range(starts.size() - 1):
		if starts[i + 1] - starts[i] > 0.05:
			pieces.append([starts[i], starts[i + 1]])
	return pieces


func _build_wall(leg: int, v_side: float, u_from: float, u_to: float) -> void:
	var cuts: Array = []
	for data in PENDULUM_DS:
		if _leg_for(data[0]) == leg:
			var pu := _leg_u(data[0], leg)
			if pu + SLOT_HALF > u_from and pu - SLOT_HALF < u_to:
				cuts.append(pu)
	cuts.sort()

	var start := u_from
	for pu in cuts:
		if pu - SLOT_HALF > start:
			_emit_wall_piece(leg, v_side, start, pu - SLOT_HALF)
		_build_pocket(leg, v_side, pu)
		start = maxf(start, pu + SLOT_HALF)
	if u_to > start:
		_emit_wall_piece(leg, v_side, start, u_to)


func _emit_wall_piece(leg: int, v_side: float, u_from: float, u_to: float) -> void:
	_leg_box(leg, (u_from + u_to) / 2.0, v_side, CEILING_Y / 2.0,
			0.4, CEILING_Y + 1.0, u_to - u_from, WALL_MATERIAL)


# A recessed pocket the blade swings into: back panel, side returns,
# floor and ceiling piece.
func _build_pocket(leg: int, v_side: float, pu: float) -> void:
	var sign := signf(v_side)
	_leg_box(leg, pu, sign * 3.8, CEILING_Y / 2.0, 0.4, CEILING_Y + 1.0, 1.8, WALL_MATERIAL)
	for du in [-0.9, 0.9]:
		_leg_box(leg, pu + du, sign * 3.0, CEILING_Y / 2.0, 1.6, CEILING_Y + 1.0, 0.4, WALL_MATERIAL)
	_leg_box(leg, pu, sign * 3.0, -0.2, 1.6, 0.4, 1.8, FLOOR_MATERIAL)
	_leg_box(leg, pu, sign * 3.0, CEILING_Y + 0.2, 1.6, 0.4, 1.8, WALL_MATERIAL)


func _build_hazards() -> void:
	for data in PENDULUM_DS:
		var leg := _leg_for(data[0])
		var pendulum: Node3D = PendulumScript.new()
		pendulum.phase_offset = data[1]
		pendulum.position = _pos(leg, _leg_u(data[0], leg), 0.0, CEILING_Y - 0.1)
		pendulum.rotation.y = LEGS[leg]["yaw"]
		add_child(pendulum)
		pendulum.player_hit.connect(_on_trap_hit)

	for row_d in CRACK_D_ROWS:
		var leg := _leg_for(row_d)
		for v in [-1.1, 1.1]:
			var tile: StaticBody3D = CrackTileScript.new()
			tile.position = _pos(leg, _leg_u(row_d, leg), v, -0.2)
			add_child(tile)


func _start_ambient_pad() -> void:
	var pad := AudioStreamPlayer.new()
	pad.stream = AMBIENT_PAD
	if pad.stream is AudioStreamMP3:
		pad.stream.loop = true
	pad.volume_db = -16.0
	pad.autoplay = true
	add_child(pad)


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

	var torch_glow := StandardMaterial3D.new()
	torch_glow.albedo_color = Color(1.0, 0.55, 0.15)
	torch_glow.emission_enabled = true
	torch_glow.emission = Color(1.0, 0.5, 0.12)
	torch_glow.emission_energy_multiplier = 2.5

	var d := 2.0
	var side := 1.0
	while d < 141.0:
		var leg := _leg_for(d)
		var u := _leg_u(d, leg)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.62, 0.28)
		light.light_energy = 2.2
		light.omni_range = 9.0
		light.position = _pos(leg, u, side * 1.8, 3.0)
		add_child(light)

		var head := MeshInstance3D.new()
		var flame := BoxMesh.new()
		flame.size = Vector3(0.18, 0.3, 0.18)
		flame.material = torch_glow
		head.mesh = flame
		head.position = _pos(leg, u, side * 2.1, 2.9)
		add_child(head)

		side = -side
		d += 8.0
