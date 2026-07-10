extends Node3D

# Level 2: The Pendulum's Journey. A linear torch-lit hall inside the
# pyramid, built from a section table: pendulums, jump holes, and
# crumbling floor tiles, combined per the level design.
const LEVEL_MUSIC: AudioStream = preload("res://soundAndMusic/music/AztekenherausforderungLevel02.mp3")
const AMBIENT_PAD: AudioStream = preload("res://soundAndMusic/sounds/Pad-Sound.mp3")
const WALL_MATERIAL: StandardMaterial3D = preload("res://materials/sandstone_sphinx.tres")
const FLOOR_MATERIAL: StandardMaterial3D = preload("res://materials/sandstone_pyramid.tres")
const PendulumScript := preload("res://hazards/pendulum.gd")
const CrackTileScript := preload("res://hazards/crack_tile.gd")

const CORRIDOR_WIDTH: float = 4.4
const WALL_X: float = 2.4
const CEILING_Y: float = 4.5
const KILL_Y: float = -6.0

# Solid floor as (z_from, z_to) segments; the gaps between them are the
# jump holes and crumble fields. Walking direction is -Z.
const FLOOR_SEGMENTS := [
	[6.0, -38.0],    # start, S1 pendulum, S2 double pendulum
	[-41.0, -48.0],  # after the jump hole (S3)
	[-52.0, -54.0],  # safe strip inside crumble field (S4)
	[-56.0, -60.0],  # after S4
	[-64.0, -66.0],  # safe strip inside S5
	[-68.0, -75.0],  # S6 approach
	[-79.0, -85.0],  # S6 middle platform
	[-89.0, -98.0],  # landing and chamber entrance
]
# Crumbling tile rows (z center); each row is two tiles across.
const CRACK_ROWS := [-49.0, -51.0, -55.0, -61.0, -63.0, -67.0, -76.0, -78.0]
# Pendulums as (z, phase offset). S2's pair swings in opposition; the
# shared clock keeps every blade predictable.
const PENDULUMS := [
	[-12.0, 0.0],
	[-24.0, 0.0],
	[-30.0, PI],
	[-63.0, 0.0],
	[-73.0, 0.9],
	[-84.0, PI * 0.6],
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

	# Torches along the walls.
	var torch_glow := StandardMaterial3D.new()
	torch_glow.albedo_color = Color(1.0, 0.55, 0.15)
	torch_glow.emission_enabled = true
	torch_glow.emission = Color(1.0, 0.5, 0.12)
	torch_glow.emission_energy_multiplier = 2.5
	var z := 2.0
	var side := 1.0
	while z > -96.0:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.62, 0.28)
		light.light_energy = 2.2
		light.omni_range = 9.0
		light.position = Vector3(side * (WALL_X - 0.5), 3.0, z)
		add_child(light)

		var head := MeshInstance3D.new()
		var flame := BoxMesh.new()
		flame.size = Vector3(0.18, 0.3, 0.18)
		flame.material = torch_glow
		head.mesh = flame
		head.position = Vector3(side * (WALL_X - 0.15), 2.9, z)
		add_child(head)

		side = -side
		z -= 8.0


func _build_geometry() -> void:
	for segment in FLOOR_SEGMENTS:
		var length: float = segment[0] - segment[1]
		_add_box(Vector3(CORRIDOR_WIDTH, 0.4, length),
				Vector3(0.0, -0.2, (segment[0] + segment[1]) / 2.0), FLOOR_MATERIAL)

	var hall_length := 6.0 - (-98.0)
	var hall_center := (6.0 + -98.0) / 2.0
	for side in [-1.0, 1.0]:
		_add_box(Vector3(0.4, CEILING_Y + 1.0, hall_length),
				Vector3(side * WALL_X, CEILING_Y / 2.0, hall_center), WALL_MATERIAL)
	_add_box(Vector3(CORRIDOR_WIDTH + 0.8, 0.4, hall_length),
			Vector3(0.0, CEILING_Y, hall_center), WALL_MATERIAL)
	_add_box(Vector3(CORRIDOR_WIDTH + 0.8, CEILING_Y + 1.0, 0.4),
			Vector3(0.0, CEILING_Y / 2.0, 6.2), WALL_MATERIAL)
	_add_box(Vector3(CORRIDOR_WIDTH + 0.8, CEILING_Y + 1.0, 0.4),
			Vector3(0.0, CEILING_Y / 2.0, -98.2), WALL_MATERIAL)

	# Dark chamber opening with the exit marker, like level 1.
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.02, 0.015, 0.01)
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_add_visual_box(Vector3(3.0, 2.8, 0.2), Vector3(0.0, 1.4, -97.9), dark)

	var sign_material := StandardMaterial3D.new()
	sign_material.albedo_color = Color(0.1, 0.85, 0.3)
	sign_material.emission_enabled = true
	sign_material.emission = Color(0.1, 0.85, 0.3)
	sign_material.emission_energy_multiplier = 2.0
	_add_visual_box(Vector3(0.9, 0.4, 0.12), Vector3(0.95, 2.4, -97.75), sign_material)


func _build_hazards() -> void:
	for data in PENDULUMS:
		var pendulum: Node3D = PendulumScript.new()
		pendulum.phase_offset = data[1]
		pendulum.position = Vector3(0.0, CEILING_Y - 0.1, data[0])
		add_child(pendulum)
		pendulum.player_hit.connect(_on_trap_hit)

	for row_z in CRACK_ROWS:
		for x in [-1.1, 1.1]:
			var tile: StaticBody3D = CrackTileScript.new()
			tile.position = Vector3(x, -0.2, row_z)
			add_child(tile)


func _add_box(size: Vector3, pos: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.position = pos
	add_child(body)
	_attach_mesh(body, size, material)


func _add_visual_box(size: Vector3, pos: Vector3, material: Material) -> void:
	var holder := Node3D.new()
	holder.position = pos
	add_child(holder)
	_attach_mesh(holder, size, material)


func _attach_mesh(parent: Node3D, size: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	mesh.mesh = box
	parent.add_child(mesh)
