extends Node3D

# Level 6: Crocodiles. The river below the pyramid flows out into the
# open. The player crosses it by running over the backs of crocodiles;
# every croc sinks now and then, and they thin out along the way. At
# the jetty a Nile steamboat waits — reach it and the level ends.

const LEVEL_MUSIC: AudioStream = preload("res://soundAndMusic/music/AztekenherausforderungLevel01.mp3")
const WALL_MATERIAL: StandardMaterial3D = preload("res://materials/sandstone_sphinx.tres")
const FLOOR_MATERIAL: StandardMaterial3D = preload("res://materials/sandstone_pyramid.tres")
const SAND_TEXTURE: Texture2D = preload("res://textures/aerial_sand_diff_1k.jpg")
const SAND_ROUGHNESS: Texture2D = preload("res://textures/aerial_sand_rough_1k.jpg")
const SAND_NORMAL: Texture2D = preload("res://textures/aerial_sand_nor_gl_1k.jpg")
const Crocodile := preload("res://hazards/crocodile.gd")
const IntroTitle := preload("res://ui/intro_title.gd")

const INTRO_HOLD: float = 1.4

const WATER_Y: float = -0.4
# The player dies once the feet are ~0.35 m under the water surface.
const KILL_CENTER_Y: float = 0.15
const RIVER_HALF_WIDTH: float = 7.0

# Crocs thin out along the river: the gap between them grows.
const CROC_COUNT: int = 20
const CROC_LENGTH: float = 2.0
const GAP_NEAR: float = 1.6
const GAP_FAR: float = 3.4

@onready var player: CharacterBody3D = $Player
@onready var god_label: Label = $ControlsHint/Root/GodLabel

# The pre-play cinematic; disabled for headless runs (tests).
@export var intro_enabled: bool = true

var _spawn_transform: Transform3D
var _croc_positions: Array[Vector3] = []
var _intro_running: bool = false
var _intro_skip: bool = false


func _ready() -> void:
	_spawn_transform = player.global_transform
	GameManager.play_music(LEVEL_MUSIC)
	_build_environment()
	_build_landscape()
	_build_crocs()
	_build_jetty_and_boat()

	god_label.visible = GameManager.god_mode
	GameManager.god_mode_changed.connect(_on_god_mode_changed)

	if intro_enabled and DisplayServer.get_name() != "headless":
		_play_intro()


func _physics_process(_delta: float) -> void:
	if to_local(player.global_position).y < KILL_CENTER_Y and not player.is_dying():
		if GameManager.god_mode:
			player.reset_to_start(_spawn_transform)
		else:
			player.die_and_reset(_spawn_transform, true, false)


func _unhandled_input(event: InputEvent) -> void:
	if _intro_running and event.is_pressed() \
			and (event is InputEventKey or event is InputEventMouseButton):
		_intro_skip = true


# ------------------------------------------------------------ landscape

func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.21, 0.42, 0.75)
	sky_material.sky_horizon_color = Color(0.86, 0.78, 0.6)
	sky_material.ground_bottom_color = Color(0.7, 0.6, 0.4)
	sky_material.ground_horizon_color = Color(0.86, 0.78, 0.6)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.fog_enabled = true
	env.fog_light_color = Color(0.88, 0.79, 0.62)
	env.fog_density = 0.004
	env.fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1, 0.88, 0.68)
	sun.light_energy = 1.3
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	add_child(sun)


# The dune sheet from Level 1, flattened along the banks — and carved
# out below the waterline where the river runs.
func _dune_height(x: float, z: float) -> float:
	var n := 0.55 * (0.5 + 0.5 * sin(x / 23.0) * cos(z / 29.0))
	n += 0.30 * (0.5 + 0.5 * sin(x / 12.0 + z / 15.0 + 1.7))
	n += 0.15 * (0.5 + 0.5 * sin((x - z) / 8.0 + 3.1))
	var flatten := smoothstep(RIVER_HALF_WIDTH + 1.5, RIVER_HALF_WIDTH + 10.0, absf(x))
	var edge := smoothstep(150.0, 130.0, absf(x)) * smoothstep(150.0, 130.0, absf(z + 50.0))
	var channel := 1.0 - smoothstep(RIVER_HALF_WIDTH - 1.0, RIVER_HALF_WIDTH + 2.5, absf(x))
	return 3.0 * n * flatten * edge - 2.2 * channel


func _build_landscape() -> void:
	var sand := StandardMaterial3D.new()
	sand.albedo_texture = SAND_TEXTURE
	sand.roughness_texture = SAND_ROUGHNESS
	sand.normal_enabled = true
	sand.normal_texture = SAND_NORMAL
	sand.uv1_scale = Vector3(0.1, 0.1, 0.1)
	sand.uv1_triplanar = true
	sand.uv1_world_triplanar = true
	sand.cull_mode = BaseMaterial3D.CULL_DISABLED

	var cell := 3.0
	var steps := 100
	var positions: Array[PackedVector3Array] = []
	for j in steps + 1:
		var z := 50.0 - float(j) * cell
		var row := PackedVector3Array()
		for i in steps + 1:
			var x := -150.0 + float(i) * cell
			row.append(Vector3(x, _dune_height(x, z), z))
		positions.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in steps:
		for i in steps:
			st.add_vertex(positions[j][i])
			st.add_vertex(positions[j + 1][i])
			st.add_vertex(positions[j][i + 1])
			st.add_vertex(positions[j][i + 1])
			st.add_vertex(positions[j + 1][i])
			st.add_vertex(positions[j + 1][i + 1])
	st.generate_normals()
	var dunes := MeshInstance3D.new()
	dunes.mesh = st.commit()
	dunes.material_override = sand
	add_child(dunes)

	# The river itself, plus its bed so the water has depth to sink into.
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.13, 0.34, 0.42, 0.8)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.1
	water.metallic = 0.3
	var river := MeshInstance3D.new()
	var river_mesh := BoxMesh.new()
	river_mesh.size = Vector3(RIVER_HALF_WIDTH * 2.0, 0.3, 180.0)
	river_mesh.material = water
	river.mesh = river_mesh
	river.position = Vector3(0, WATER_Y - 0.15, -55.0)
	add_child(river)
	_add_box(Vector3(0, -3.2, -55.0), Vector3(RIVER_HALF_WIDTH * 2.0, 0.4, 180.0),
			FLOOR_MATERIAL, false)

	# Invisible banks keep the crossing on the crocodiles.
	for side: float in [-1.0, 1.0]:
		_add_box(Vector3(side * (RIVER_HALF_WIDTH + 0.6), 1.5, -38.0),
				Vector3(1.0, 4.0, 100.0), FLOOR_MATERIAL, false, false)

	# The pyramid face the river flows out of, with a dark mouth.
	_add_box(Vector3(-16.5, 7.0, 13.0), Vector3(23.0, 14.0, 1.6), WALL_MATERIAL)
	_add_box(Vector3(16.5, 7.0, 13.0), Vector3(23.0, 14.0, 1.6), WALL_MATERIAL)
	_add_box(Vector3(0, 10.5, 13.0), Vector3(10.0, 7.0, 1.6), WALL_MATERIAL)
	_add_box(Vector3(0, 16.0, 13.0), Vector3(40.0, 4.0, 1.4), WALL_MATERIAL)
	_add_box(Vector3(0, 19.5, 13.0), Vector3(28.0, 3.5, 1.2), WALL_MATERIAL)
	_add_box(Vector3(0, 22.5, 13.0), Vector3(16.0, 2.8, 1.0), WALL_MATERIAL)
	var dark := StandardMaterial3D.new()
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.albedo_color = Color(0.02, 0.015, 0.01)
	var mouth := MeshInstance3D.new()
	var mouth_mesh := BoxMesh.new()
	mouth_mesh.size = Vector3(10.0, 7.0, 0.3)
	mouth_mesh.material = dark
	mouth.mesh = mouth_mesh
	mouth.position = Vector3(0, 3.5, 13.2)
	add_child(mouth)

	# The stone ledge the player starts on, in front of the pyramid mouth
	# (far enough out that the chase camera stays clear of the facade).
	_add_box(Vector3(0, -0.3, 8.5), Vector3(6.0, 1.0, 5.0), FLOOR_MATERIAL)

	# Palms along the banks.
	for data: Array in [[-11.0, -8.0, 4.6], [12.0, -20.0, 5.4], [-13.0, -42.0, 5.0],
			[10.5, -58.0, 4.4], [-10.0, -74.0, 5.6], [13.5, -90.0, 4.8],
			[-11.5, -103.0, 5.2], [9.5, 2.0, 4.5]]:
		var palm := NileProps.build_palm(data[2])
		palm.position = Vector3(data[0], _dune_height(data[0], data[1]) - 0.1, data[1])
		palm.rotation.y = data[0] * 2.1
		add_child(palm)


func _build_crocs() -> void:
	var z := 5.0
	for i in CROC_COUNT:
		var x := sin(float(i) * 1.7) * 1.3
		var croc: AnimatableBody3D = Crocodile.new()
		croc.surface_y = -0.15
		croc.position = Vector3(x, -0.15, z)
		croc.rotation.y = sin(float(i) * 2.3) * 0.25
		add_child(croc)
		_croc_positions.append(Vector3(x, -0.15, z))
		var gap := lerpf(GAP_NEAR, GAP_FAR, float(i) / float(CROC_COUNT - 1))
		z -= CROC_LENGTH + gap


func _build_jetty_and_boat() -> void:
	# A wooden jetty from the last crocodiles to the moored steamboat.
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.3, 0.18)
	wood.roughness = 0.95
	var jetty_from: float = _croc_positions[CROC_COUNT - 1].z - 3.0
	var jetty_to: float = jetty_from - 14.0
	_add_box(Vector3(0, 0.05, (jetty_from + jetty_to) / 2.0),
			Vector3(3.0, 0.3, jetty_from - jetty_to), wood)
	for i in 4:
		var post_z: float = jetty_from - 1.0 - i * 4.0
		for side: float in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var post_mesh := CylinderMesh.new()
			post_mesh.top_radius = 0.12
			post_mesh.bottom_radius = 0.12
			post_mesh.height = 1.6
			post_mesh.material = wood
			post.mesh = post_mesh
			post.position = Vector3(side * 1.4, -0.4, post_z)
			add_child(post)

	var boat := NileProps.build_boat()
	boat.position = Vector3(5.4, WATER_Y + 0.5, jetty_to - 2.0)
	boat.rotation.y = 0.1
	add_child(boat)


func _add_box(center: Vector3, size: Vector3, material: Material,
		visual: bool = true, with_collision: bool = true) -> void:
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
	add_child(parent)


func _on_god_mode_changed(enabled: bool) -> void:
	god_label.visible = enabled


# ---------------------------------------------------------------- intro

# A ~4 s cinematic: the camera drifts over the river, crocodiles below
# and the steamboat far ahead, zooming in and back out; mid-shot the
# frame freezes for the level title. Any key or click skips it.
func _play_intro(duration: float = 4.0) -> void:
	_intro_running = true
	_intro_skip = false
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	var pause_menu: Node = get_node_or_null("PauseMenu")
	if pause_menu:
		pause_menu.set_process_unhandled_input(false)

	var cam := Camera3D.new()
	add_child(cam)
	var title := IntroTitle.new()
	title.setup("Level 6", "Crocodiles")
	title.visible = false
	add_child(title)

	var hold := INTRO_HOLD * duration / 4.0
	var tree := get_tree()
	var elapsed := 0.0
	var held := 0.0
	while elapsed < duration and not _intro_skip:
		if not is_inside_tree():
			return
		var t := elapsed / duration
		cam.fov = 68.0 - 24.0 * sin(PI * t)
		cam.global_position = to_global(Vector3(
				3.5 - 1.5 * t, 3.2 - 1.0 * sin(PI * t), 6.0 - 10.0 * t))
		cam.look_at(to_global(Vector3(0, -0.2, -30.0 - 20.0 * t)), Vector3.UP)
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
	player.set_physics_process(true)
	_intro_running = false
