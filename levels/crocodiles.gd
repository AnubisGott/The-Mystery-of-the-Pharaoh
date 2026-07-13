extends Node3D

# Level 6: Crocodiles. The river below the pyramid flows out into the
# open. The player crosses it by running over the backs of crocodiles;
# every croc sinks now and then, and they thin out along the way. At
# the jetty a Nile steamboat waits — reach it and the level ends.

const LEVEL_MUSIC: AudioStream = preload("res://soundAndMusic/music/AztekenherausforderungLevel06.mp3")
const WALL_MATERIAL: StandardMaterial3D = preload("res://materials/sandstone_sphinx.tres")
const FLOOR_MATERIAL: StandardMaterial3D = preload("res://materials/sandstone_pyramid.tres")
const SAND_TEXTURE: Texture2D = preload("res://textures/aerial_sand_diff_1k.jpg")
const SAND_ROUGHNESS: Texture2D = preload("res://textures/aerial_sand_rough_1k.jpg")
const SAND_NORMAL: Texture2D = preload("res://textures/aerial_sand_nor_gl_1k.jpg")
const Crocodile := preload("res://hazards/crocodile.gd")
const IntroTitle := preload("res://ui/intro_title.gd")
const TouchControls := preload("res://ui/touch_controls.gd")
const SPLASH_SOUND: AudioStream = preload("res://sounds/splash_blub.wav")

const INTRO_HOLD: float = 1.4

const WATER_Y: float = -0.4
# The player dies once the feet are ~0.35 m under the water surface.
const KILL_CENTER_Y: float = 0.15
const RIVER_HALF_WIDTH: float = 7.0

# Crocs thin out along the river: the gap between them grows. The
# quadratic ramp keeps the start dense and the finish sparse.
const CROC_COUNT: int = 22
const CROC_LENGTH: float = 2.0
const GAP_NEAR: float = 1.2
const GAP_FAR: float = 3.4

# The Android port turns the crossing into hops: each button leaps once
# in its direction. Late in the river the backs lie up to ~5.4 m apart,
# too far to aim by eye, so a hop locks onto the nearest surfaced croc
# in that direction and flies a ballistic arc to it.
const HOP_RADIUS: float = 52.0
const HOP_JUMP_VELOCITY: float = 5.2
const HOP_MAX_DISTANCE: float = 6.2
const HOP_MIN_DISTANCE: float = 0.6
const HOP_CONE: float = 0.5          # how far off-axis a croc may lie
const HOP_DEFAULT_DISTANCE: float = 3.0   # nothing to aim at: a plain leap
const HOP_MAX_SPEED: float = 11.0
const CROC_SUNK_MARGIN: float = 0.25

@onready var player: CharacterBody3D = $Player
@onready var god_label: Label = $ControlsHint/Root/GodLabel

# The pre-play cinematic; disabled for headless runs (tests).
@export var intro_enabled: bool = true

var _spawn_transform: Transform3D
var _croc_positions: Array[Vector3] = []
var _splash_player: AudioStreamPlayer
var _god_walkway: CollisionShape3D
var _dock_end_z: float = 0.0
var _intro_running: bool = false
var _intro_skip: bool = false
var _intro_can_skip: bool = false
var _outro_running: bool = false
var _hop_buttons: Array[Dictionary] = []
var _hopping: bool = false
var _hop_request: Vector3 = Vector3.ZERO
var _hop_request_age: float = 0.0


func _ready() -> void:
	_spawn_transform = player.global_transform
	GameManager.play_music(LEVEL_MUSIC)
	_build_environment()
	_build_landscape()
	_build_crocs()
	_build_jetty_and_boat()

	_splash_player = AudioStreamPlayer.new()
	_splash_player.stream = SPLASH_SOUND
	_splash_player.volume_db = -4.0
	_splash_player.bus = "Sfx"
	add_child(_splash_player)

	# God mode turns the river into solid ground: an invisible walkway
	# just above the water carries the player all the way to the jetty.
	var walkway := StaticBody3D.new()
	_god_walkway = CollisionShape3D.new()
	var walkway_shape := BoxShape3D.new()
	walkway_shape.size = Vector3(RIVER_HALF_WIDTH * 2.0, 0.3, 150.0)
	_god_walkway.shape = walkway_shape
	_god_walkway.disabled = not GameManager.god_mode
	walkway.add_child(_god_walkway)
	walkway.position = Vector3(0, WATER_Y - 0.1, -55.0)
	add_child(walkway)

	god_label.visible = GameManager.god_mode
	GameManager.god_mode_changed.connect(_on_god_mode_changed)

	if GameManager.touch_mode:
		_setup_touch_mode()

	if intro_enabled and DisplayServer.get_name() != "headless":
		_play_intro()


# Android port scheme for Level 6: four buttons, one hop each. No free
# walking - the crossing becomes a leap from back to back.
func _setup_touch_mode() -> void:
	get_node("ControlsHint").visible = false
	var touch: CanvasLayer = TouchControls.new()
	add_child(touch)
	# A cross under the right thumb: forward up, back down, left and
	# right beside them (col counts inward from the right edge).
	_hop_buttons = [
		{"dir": Vector3(0, 0, -1), "node": touch.add_button("^", "", true, 1, 2, HOP_RADIUS)},
		{"dir": Vector3(0, 0, 1), "node": touch.add_button("v", "", true, 1, 0, HOP_RADIUS)},
		{"dir": Vector3(-1, 0, 0), "node": touch.add_button("<", "", true, 2, 1, HOP_RADIUS)},
		{"dir": Vector3(1, 0, 0), "node": touch.add_button(">", "", true, 0, 1, HOP_RADIUS)},
	]
	# Edge-triggered: a quick tap can begin and end between two physics
	# frames, and polling the button would never see it.
	for entry in _hop_buttons:
		var button: TouchScreenButton = entry["node"]
		button.pressed.connect(_on_hop_pressed.bind(entry["dir"]))
	touch.add_pause_button()


func _on_hop_pressed(direction: Vector3) -> void:
	_hop_request = direction
	_hop_request_age = 0.0


func _drive_hops(delta: float) -> void:
	if _intro_running or _outro_running or player.is_dying():
		_hop_request = Vector3.ZERO
		return

	# A hop ends when the feet are back on something solid.
	if _hopping:
		if player.is_on_floor() and player.velocity.y <= 0.01:
			_hopping = false
			player.external_motion = false
		return

	if _hop_request == Vector3.ZERO:
		return
	if player.is_on_floor():
		var direction := _hop_request
		_hop_request = Vector3.ZERO
		_hop(direction)
		return
	# Tapped mid-air: hold it briefly, then drop it.
	_hop_request_age += delta
	if _hop_request_age > 0.25:
		_hop_request = Vector3.ZERO


# One leap in `direction`, aimed at the nearest surfaced croc that way.
func _hop(direction: Vector3) -> void:
	var from: Vector3 = player.global_position
	var target: Vector3 = _hop_target(direction, from)
	var flat := Vector2(target.x - from.x, target.z - from.z)
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var air_time: float = 2.0 * HOP_JUMP_VELOCITY / gravity
	var speed: float = minf(flat.length() / air_time, HOP_MAX_SPEED)
	var course := flat.normalized() * speed

	player.velocity = Vector3(course.x, HOP_JUMP_VELOCITY, course.y)
	player.external_motion = true
	_hopping = true
	# Leap facing the way he is going.
	player.rotation.y = atan2(-direction.x, -direction.z)
	player._yaw = player.rotation.y
	var anim: AnimationPlayer = player.get_node("Visual/AnimationPlayer")
	anim.speed_scale = 1.0
	anim.play("Jump_Start", 0.1)


# The nearest surfaced croc within reach in `direction`; a plain leap
# when there is nothing to aim at (into the water, most likely).
func _hop_target(direction: Vector3, from: Vector3) -> Vector3:
	var best: Node3D = null
	var best_distance := INF
	for croc in get_tree().get_nodes_in_group("crocodiles"):
		if not is_ancestor_of(croc):
			continue
		if croc.position.y < croc.surface_y - CROC_SUNK_MARGIN:
			continue   # under water: no landing spot
		var to_croc: Vector3 = croc.global_position - from
		to_croc.y = 0.0
		var distance := to_croc.length()
		if distance < HOP_MIN_DISTANCE or distance > HOP_MAX_DISTANCE:
			continue
		if to_croc.normalized().dot(direction) < HOP_CONE:
			continue
		if distance < best_distance:
			best_distance = distance
			best = croc
	if best != null:
		return Vector3(best.global_position.x, from.y, best.global_position.z)
	return from + direction * HOP_DEFAULT_DISTANCE


func _physics_process(delta: float) -> void:
	if GameManager.touch_mode:
		_drive_hops(delta)

	if to_local(player.global_position).y < KILL_CENTER_Y and not player.is_dying():
		# Blub blub blub: going under is audible.
		_splash_player.play()
		if GameManager.god_mode:
			player.reset_to_start(_spawn_transform)
		else:
			player.die_and_reset(_spawn_transform, true, false)


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
	# It runs the whole carved channel to the far edge of the dune sheet,
	# so from the jetty the canal reaches the horizon.
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.13, 0.34, 0.42, 0.8)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.1
	water.metallic = 0.3
	var river := MeshInstance3D.new()
	var river_mesh := BoxMesh.new()
	river_mesh.size = Vector3(RIVER_HALF_WIDTH * 2.0, 0.3, 280.0)
	river_mesh.material = water
	river.mesh = river_mesh
	river.position = Vector3(0, WATER_Y - 0.15, -105.0)
	add_child(river)
	_add_box(Vector3(0, -3.2, -105.0), Vector3(RIVER_HALF_WIDTH * 2.0, 0.4, 280.0),
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
	# The dark tunnel mouth doubles as a solid wall: the player cannot
	# walk back into the pyramid, and the chase camera's spring arm
	# collides with it instead of slipping behind the facade.
	var dark := StandardMaterial3D.new()
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.albedo_color = Color(0.02, 0.015, 0.01)
	_add_box(Vector3(0, 3.5, 13.0), Vector3(10.0, 7.0, 0.3), dark)

	# The stone ledge the player starts on: it reaches through the
	# pyramid mouth so there is no gap to the facade at all.
	_add_box(Vector3(0, -0.3, 9.9), Vector3(6.0, 1.0, 7.8), FLOOR_MATERIAL)

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
	# The warm-up raft off the ledge: three rows of crocs side by side,
	# head to tail — nearly a walkway.
	for row in 3:
		for x_side: float in [-0.8, 0.8]:
			var raft_croc: AnimatableBody3D = Crocodile.new()
			raft_croc.surface_y = -0.15
			raft_croc.position = Vector3(x_side, -0.15, z)
			add_child(raft_croc)
			_croc_positions.append(Vector3(x_side, -0.15, z))
		z -= CROC_LENGTH + 0.4

	# After the raft they scatter, and the gaps open up toward the end.
	var scattered := CROC_COUNT - 6
	for i in scattered:
		var x := sin(float(i) * 1.7) * 1.3
		var croc: AnimatableBody3D = Crocodile.new()
		croc.surface_y = -0.15
		croc.position = Vector3(x, -0.15, z)
		croc.rotation.y = sin(float(i) * 2.3) * 0.25
		add_child(croc)
		_croc_positions.append(Vector3(x, -0.15, z))
		var gap := lerpf(GAP_NEAR, GAP_FAR, pow(float(i) / float(scattered - 1), 2.0))
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

	# The steamboat moors alongside the dock, its paddle box a step from
	# the planks, ready to leave for Level 7.
	var boat := NileProps.build_boat()
	boat.position = Vector3(3.6, WATER_Y + 0.5, (jetty_from + jetty_to) / 2.0)
	boat.rotation.y = 0.1
	add_child(boat)

	# The finish line sits a quarter of the way down the dock: the
	# landing steps still belong to the crossing, everything beyond
	# that line ends the level. Anchored and sized here in code: the
	# jetty is laid out relative to the last croc, so a fixed end zone
	# drifts off into open water whenever the croc layout is retuned.
	var zone_from := jetty_from - (jetty_from - jetty_to) * 0.25
	var zone_to := jetty_to - 1.0
	var end_zone: Area3D = get_node("EndZone")
	end_zone.position = Vector3(0, 1.2, (zone_from + zone_to) / 2.0)
	var end_shape: BoxShape3D = end_zone.get_node("CollisionShape3D").shape
	end_shape.size = Vector3(3.6, 3.0, zone_from - zone_to)

	# Reaching the line does not cut straight to Level 7: the zone hands
	# over to the slow-motion finale below.
	_dock_end_z = jetty_to
	end_zone.custom_finale = true
	end_zone.player_entered.connect(_on_end_zone_entered)


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
	_god_walkway.set_deferred("disabled", not enabled)


# ---------------------------------------------------------------- intro

func _unhandled_input(event: InputEvent) -> void:
	# Esc skips the intro or the finale - a fresh press only, ignoring
	# key repeats and input left over from gameplay (grace period).
	if (_intro_running or _outro_running) and _intro_can_skip \
			and event is InputEventKey \
			and event.is_pressed() and not event.is_echo() \
			and event.physical_keycode == KEY_ESCAPE:
		_intro_skip = true


# A ~4 s cinematic: the camera drifts over the river, crocodiles below
# and the steamboat far ahead, zooming in and back out; mid-shot the
# frame freezes for the level title. Esc skips it.
func _play_intro(duration: float = 4.0) -> void:
	_intro_running = true
	_intro_skip = false
	_intro_can_skip = false
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	var pause_menu: Node = get_node_or_null("PauseMenu")
	if pause_menu:
		pause_menu.set_process_unhandled_input(false)

	var cam := Camera3D.new()
	add_child(cam)
	var title := IntroTitle.new()
	title.setup(tr("Level %d") % 6, tr("Crocodiles"))
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


# ---------------------------------------------------------------- outro

func _on_end_zone_entered() -> void:
	if _outro_running:
		return
	_outro_running = true
	if DisplayServer.get_name() != "headless":
		# body_entered fires while physics is flushing; the cutscene
		# adds nodes, so it must wait for the flush to finish.
		# (_play_outro_run is the older run-only finale, kept as a
		# drop-in replacement.)
		_play_outro_jump.call_deferred()
	else:
		GameManager.complete_level()


# The finale: the adventurer sprints down the dock in slow motion,
# veers to the edge and leaps for the steamer's open foredeck - the cut
# to Level 7 comes right at the highest point of the jump, landing
# unseen. Esc skips straight to Level 7.
func _play_outro_jump() -> void:
	_intro_skip = false
	_intro_can_skip = true
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	var pause_menu: Node = get_node_or_null("PauseMenu")
	if pause_menu:
		pause_menu.set_process_unhandled_input(false)
	get_node("ControlsHint").visible = false   # no HUD over the cutscene

	var anim: AnimationPlayer = player.get_node("Visual/AnimationPlayer")
	anim.speed_scale = 1.0
	anim.play("Running_A", 0.2)
	player.rotation.y = 0.0   # squarely down the dock

	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.make_current()

	Engine.time_scale = 0.35
	var tree := get_tree()
	var y0 := player.global_position.y

	# Three legs: down the dock, two veering steps to the dock edge,
	# and the rising half of the leap. The apex hangs over the gap
	# between the planks and the hull; the implied landing is the open
	# main deck by the bow.
	var run_to := to_global(Vector3(0.0, 0, _dock_end_z + 5.2))
	var takeoff := to_global(Vector3(1.1, 0, _dock_end_z + 3.6))
	var apex := to_global(Vector3(1.75, 0, _dock_end_z + 2.3))
	run_to.y = y0
	takeoff.y = y0
	apex.y = y0 + 1.2

	var cam_low := Vector3(-4.4, 0.35, -2.2)
	var cam_mid := Vector3(-4.4, 0.8, -2.2)
	var cam_high := Vector3(-5.2, 1.25, -2.8)
	# Each leg: destination, stride speed, is-the-jump, camera from/to.
	var legs: Array[Array] = [
		[run_to, player.run_stride_speed, false, cam_low, cam_mid],
		[takeoff, player.run_stride_speed, false, cam_mid, cam_mid],
		[apex, 4.2, true, cam_mid, cam_high],
	]
	for leg in legs:
		if _intro_skip:
			break
		var from := player.global_position
		var to: Vector3 = leg[0]
		var flat := Vector2(to.x - from.x, to.z - from.z)
		var heading := atan2(-flat.x, -flat.y)
		var start_yaw := player.rotation.y
		var jumping: bool = leg[2]
		if jumping:
			anim.play("Jump_Start", 0.1)
		var t := 0.0
		while t < 1.0 and not _intro_skip:
			if not is_inside_tree():
				Engine.time_scale = 1.0
				return
			t = minf(t + get_process_delta_time() * leg[1] / maxf(flat.length(), 0.1), 1.0)
			var pos := from.lerp(to, t)
			if jumping:
				# Only the rising half of the arc: the climb eases out
				# so the vertical speed hits zero exactly at the apex.
				pos.y = from.y + (to.y - from.y) * sin(t * PI / 2.0)
				if anim.current_animation.is_empty():
					anim.play("Jump_Idle", 0.2)   # takeoff clip finished
			player.rotation.y = lerp_angle(start_yaw, heading, minf(t * 3.0, 1.0))
			player.global_position = pos
			var focus := pos + Vector3(0, 0.75, 0)
			cam.global_position = focus + (leg[3] as Vector3).lerp(leg[4], t)
			cam.look_at(focus + Vector3(1.2, 0.15, -1.0), Vector3.UP)
			await tree.process_frame

	# A short hang on the apex - then the journey home begins.
	var hold := 0.0
	while hold < 0.15 and not _intro_skip:
		if not is_inside_tree():
			Engine.time_scale = 1.0
			return
		await tree.process_frame
		hold += get_process_delta_time()

	Engine.time_scale = 1.0
	GameManager.complete_level()


# The older finale, kept as a drop-in replacement (swap the call in
# _on_end_zone_entered): the adventurer covers the last stretch of the
# dock in slow motion and pulls up facing the ship, without jumping
# aboard. Esc skips straight to Level 7.
func _play_outro_run() -> void:
	_intro_skip = false
	_intro_can_skip = true
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	var pause_menu: Node = get_node_or_null("PauseMenu")
	if pause_menu:
		pause_menu.set_process_unhandled_input(false)
	get_node("ControlsHint").visible = false   # no HUD over the cutscene

	var anim: AnimationPlayer = player.get_node("Visual/AnimationPlayer")
	anim.speed_scale = 1.0
	anim.play("Running_A", 0.2)
	player.rotation.y = 0.0   # squarely down the dock

	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.make_current()

	Engine.time_scale = 0.35
	var tree := get_tree()
	var from := player.global_position
	var target := to_global(Vector3(0, 0, _dock_end_z + 3.5))
	target.y = from.y
	var travel := maxf(absf(from.z - target.z), 0.1)
	var t := 0.0
	while t < 1.0 and not _intro_skip:
		if not is_inside_tree():
			Engine.time_scale = 1.0
			return
		# The stride pace matches the run clip, so the slow motion is
		# pure time_scale - no moonwalking.
		t = minf(t + get_process_delta_time() * player.run_stride_speed / travel, 1.0)
		player.global_position = from.lerp(target, t)
		var focus := player.global_position + Vector3(0, 0.75, 0)
		cam.global_position = focus + Vector3(-4.4, 0.35 + 0.45 * t, -2.2)
		cam.look_at(focus + Vector3(1.2, 0, -1.0), Vector3.UP)
		await tree.process_frame

	# Arrived: pull out of the sprint and turn to face the ship.
	anim.play("Idle", 0.3)
	var hold := 0.0
	while hold < 0.6 and not _intro_skip:
		if not is_inside_tree():
			Engine.time_scale = 1.0
			return
		player.rotation.y = lerp_angle(0.0, -PI / 2.0, minf(hold / 0.35, 1.0))
		var focus := player.global_position + Vector3(0, 0.75, 0)
		cam.global_position = focus + Vector3(-4.4, 0.8, -2.2)
		cam.look_at(focus + Vector3(1.2, 0.2, -1.0), Vector3.UP)
		await tree.process_frame
		hold += get_process_delta_time()

	Engine.time_scale = 1.0
	GameManager.complete_level()
