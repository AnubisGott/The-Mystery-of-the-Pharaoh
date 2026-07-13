extends Node3D

const SANDSTONE_MATERIAL: StandardMaterial3D = preload("res://materials/sandstone_sphinx.tres")
const LEVEL_MUSIC: AudioStream = preload("res://soundAndMusic/music/AztekenherausforderungLevel01.mp3")
const PYRAMID_MATERIAL: StandardMaterial3D = preload("res://materials/sandstone_pyramid.tres")
const IntroTitle := preload("res://ui/intro_title.gd")
const TouchControls := preload("res://ui/touch_controls.gd")

# How long the intro freezes mid-shot to stamp the level name on the
# frame, at the standard 4 s duration (it scales with the duration).
const INTRO_HOLD: float = 1.4

const PATH_HALF_WIDTH: float = 1.5
# The curve starts 20 m behind the player spawn (z=29) so the path
# visibly continues behind the start instead of ending at the feet.
const START_Z: float = 50.0
# The path runs slightly into the back wall of the sphinx passage
# (rear body front face at z=-96.7) so no sand shows before the
# dark exit opening.
const END_Z: float = -97.0
const AMPLITUDE: float = 3.0
const WAVELENGTH: float = 15.0
const SAMPLE_STEP: float = 1.0

# Gentle dune field around the path. The walkable path stays flat (the
# player is clamped to it and stands on the flat Sand collision box); the
# surrounding sand rolls up into low dunes purely as scenery.
const DUNE_HEIGHT: float = 3.1
const DUNE_AREA: float = 150.0        # half-extent of the sand grid (m)
const DUNE_CELL: float = 2.5          # grid resolution (m)
const DUNE_FLAT_RADIUS: float = 4.0   # fully flat within this of the path
const DUNE_RAMP: float = 9.0          # rise to full dune height over this
const DUNE_EDGE_FADE: float = 20.0    # taper back to y=0 near the grid rim
const ROCK_COUNT: int = 16

# The path is straight before/after these, winding in between.
const WINDING_START_Z: float = 20.0
const WINDING_END_Z: float = -80.0
const WINDING_FADE: float = 6.0

const SPEAR_MIN_INTERVAL: float = 1.6
const SPEAR_MAX_INTERVAL: float = 3.0

# Practice near the start: spears alternate low (jump) and high (duck)
# in a fixed rhythm. Random spears only begin past the practice zone.
const PRACTICE_INTERVAL: float = 2.4
# A gentler lead-in before the very first spear so the player can settle
# in; regular practice spacing takes over afterwards.
const INITIAL_SPEAR_DELAY: float = 2.0
const RANDOM_SPEARS_START_Z: float = 18.0
# Past the sphinx's paw line the player walks sheltered between its
# legs: no spears on the last meters to the exit.
const SPEAR_SHELTER_Z: float = -88.0

@onready var player: CharacterBody3D = $Player
@onready var track: Path3D = $Track
@onready var spear_layer: CanvasLayer = $SpearLayer
@onready var god_label: Label = $ControlsHint/Root/GodLabel

# The pre-play cinematic; disabled for headless runs (tests).
@export var intro_enabled: bool = true

var _spawn_transform: Transform3D
var _spear_timer: Timer
var _practice_timer: Timer
var _practice_high: bool = false
var _intro_running: bool = false
var _intro_skip: bool = false
var _intro_can_skip: bool = false


func _ready() -> void:
	track.curve = _build_curve()
	_build_dunes()
	_build_rocks()
	_spawn_transform = player.global_transform
	GameManager.play_music(LEVEL_MUSIC)
	spear_layer.player_hit.connect(_on_player_hit)
	god_label.visible = GameManager.god_mode
	# Named method, not a lambda: connections from the autoload's signal
	# to a lambda capture this scene strongly and leak it on scene change.
	GameManager.god_mode_changed.connect(_on_god_mode_changed)

	# The pyramid GLB carries geometry only; the triplanar sandstone
	# material needs no UVs. The sphinx scan keeps its own photo texture.
	for mesh in $Monument/Pyramid.find_children("*", "MeshInstance3D"):
		mesh.material_override = PYRAMID_MATERIAL

	# Desert bounce light: sand reflects plenty of sun, so a soft
	# shadowless fill from the opposite side keeps the sun-averted faces
	# (the back of the sphinx's head) from going near-black.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25.0, 180.0, 0.0)
	fill.light_color = Color(0.95, 0.85, 0.7)
	fill.light_energy = 0.6
	fill.shadow_enabled = false
	add_child(fill)

	_spear_timer = Timer.new()
	_spear_timer.one_shot = true
	_spear_timer.timeout.connect(_on_spear_timer_timeout)
	add_child(_spear_timer)

	_practice_timer = Timer.new()
	_practice_timer.wait_time = INITIAL_SPEAR_DELAY
	_practice_timer.timeout.connect(_on_practice_timer_timeout)
	add_child(_practice_timer)

	# Every death restarts the level, so restart the spear sequence too:
	# the long lead-in and the slow first spear come back each time.
	player.respawned.connect(_on_player_respawned)

	if GameManager.touch_mode:
		_setup_touch_mode()

	# A short cinematic before play; the spear timers start after it.
	# Headless runs (tests) go straight to gameplay.
	if intro_enabled and DisplayServer.get_name() != "headless":
		_play_intro()
	else:
		_start_spear_timers()


# Android port scheme for Level 1: the adventurer runs the path on his
# own; the player only times jumps and ducks via the two buttons.
func _setup_touch_mode() -> void:
	get_node("ControlsHint").visible = false
	var touch: CanvasLayer = TouchControls.new()
	add_child(touch)
	touch.add_button(tr("JUMP"), "jump", true)
	touch.add_button(tr("DUCK"), "duck", false)
	touch.add_pause_button()


# Steers the player along the track and keeps him moving; jumping and
# ducking stay with the player (the touch buttons press the actions).
func _drive_auto_run(delta: float) -> void:
	if _intro_running or player.is_dying():
		Input.action_release("move_forward")
		return
	var p := player.global_position
	var offset := track.curve.get_closest_offset(Vector3(p.x, 0.0, p.z))
	var ahead := track.curve.sample_baked(minf(offset + 4.0, track.curve.get_baked_length()))
	var direction := Vector3(ahead.x - p.x, 0.0, ahead.z - p.z)
	if direction.length_squared() > 0.01:
		var heading := atan2(-direction.x, -direction.z)
		player.rotation.y = lerp_angle(player.rotation.y, heading, minf(delta * 6.0, 1.0))
		player._yaw = player.rotation.y
	Input.action_press("move_forward")


func _exit_tree() -> void:
	# Auto-run holds move_forward down; do not leak it into other scenes.
	if GameManager.touch_mode:
		Input.action_release("move_forward")


func _start_spear_timers() -> void:
	_restart_spear_timer()
	_practice_timer.start()


func _unhandled_input(event: InputEvent) -> void:
	# Esc skips the intro - a fresh press only, ignoring key repeats
	# and input left over from the previous level (grace period).
	if _intro_running and _intro_can_skip and event is InputEventKey \
			and event.is_pressed() and not event.is_echo() \
			and event.physical_keycode == KEY_ESCAPE:
		_intro_skip = true


# A ~4 s cinematic: a spear glides past in slow motion while the
# adventurer ducks under it, the camera zooming in and back out.
# Esc skips it; gameplay starts afterwards.
func _play_intro(duration: float = 4.0) -> void:
	_intro_running = true
	_intro_skip = false
	_intro_can_skip = false
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	var pause_menu: Node = get_node_or_null("PauseMenu")
	if pause_menu:
		pause_menu.set_process_unhandled_input(false)
	var anim: AnimationPlayer = player.get_node("Visual/AnimationPlayer")
	anim.play("Crouch_Idle", 0.3)

	var feet: Vector3 = player.global_position + Vector3.DOWN * 0.9
	var spear := _build_intro_spear()
	add_child(spear)
	var cam := Camera3D.new()
	add_child(cam)
	var title := IntroTitle.new()
	title.setup(tr("Level %d") % 1, tr("The Path of the Sphinx"))
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
		# The spear crosses the path in slow motion, grazing duck height.
		spear.global_position = feet + Vector3(lerpf(-8.0, 8.0, t), 1.45, 0.0)
		# One smooth zoom in and back out over the whole sequence.
		cam.fov = 70.0 - 28.0 * sin(PI * t)
		cam.global_position = feet + Vector3(
				3.4 - 1.2 * sin(PI * t), 1.5, 2.4 - 0.9 * sin(PI * t))
		cam.look_at(feet + Vector3(0, 1.25, 0), Vector3.UP)
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
	spear.queue_free()
	var player_cam: Camera3D = player.get_node("CameraPivot/CameraArm/Camera3D")
	player_cam.make_current()
	cam.queue_free()
	anim.play("Idle", 0.3)
	if pause_menu:
		pause_menu.set_process_unhandled_input(true)
	player.set_process_unhandled_input(true)
	player.set_physics_process(true)
	_intro_running = false
	_start_spear_timers()


func _build_intro_spear() -> Node3D:
	# A simple 3D spear for the cinematic: wooden shaft, steel tip,
	# flying along +X (across the path).
	var spear := Node3D.new()
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.3, 0.16)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.75, 0.75, 0.78)
	steel.metallic = 0.8
	steel.roughness = 0.35

	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.022
	shaft_mesh.bottom_radius = 0.022
	shaft_mesh.height = 1.8
	shaft_mesh.material = wood
	shaft.mesh = shaft_mesh
	shaft.rotation.z = PI / 2.0
	spear.add_child(shaft)

	var tip := MeshInstance3D.new()
	var tip_mesh := CylinderMesh.new()
	tip_mesh.top_radius = 0.0
	tip_mesh.bottom_radius = 0.05
	tip_mesh.height = 0.25
	tip_mesh.material = steel
	tip.mesh = tip_mesh
	tip.rotation.z = -PI / 2.0
	tip.position = Vector3(1.0, 0.0, 0.0)
	spear.add_child(tip)
	return spear


func _build_curve() -> Curve3D:
	var curve := Curve3D.new()
	var z := START_Z
	while z >= END_Z - 0.01:
		curve.add_point(Vector3(_path_x(z), 0.0, z))
		z -= SAMPLE_STEP
	return curve


# The path winds left and right like a snake in its middle section;
# the start and the end are straight. A smoothstep envelope fades the
# winding in and out so there are no kinks.
func _path_x(z: float) -> float:
	if z >= WINDING_START_Z or z <= WINDING_END_Z:
		return 0.0

	var fade_in := (WINDING_START_Z - z) / WINDING_FADE
	var fade_out := (z - WINDING_END_Z) / WINDING_FADE
	var envelope := clampf(minf(fade_in, fade_out), 0.0, 1.0)
	envelope = envelope * envelope * (3.0 - 2.0 * envelope)

	return AMPLITUDE * envelope * sin(TAU * (WINDING_START_Z - z) / WAVELENGTH)


# Rolling height of the surrounding sand at (x, z): a few overlapping
# swells give organic dunes, flattened to zero along the path corridor
# and faded back to zero at the far rim so the sheet meets the ground
# plane cleanly.
func _dune_height(x: float, z: float) -> float:
	var n := 0.55 * (0.5 + 0.5 * sin(x / 23.0) * cos(z / 29.0))
	n += 0.30 * (0.5 + 0.5 * sin(x / 12.0 + z / 15.0 + 1.7))
	n += 0.15 * (0.5 + 0.5 * sin((x - z) / 8.0 + 3.1))
	return DUNE_HEIGHT * n * _dune_flatten(x, z) * _dune_edge(x, z)


# 0 on the path (and just beside it), easing to 1 out in the dunes.
func _dune_flatten(x: float, z: float) -> float:
	var cz := clampf(z, END_Z, START_Z)
	var d := absf(x - _path_x(cz))
	if z > START_Z:
		d = maxf(d, z - START_Z)
	elif z < END_Z:
		d = maxf(d, END_Z - z)
	return smoothstep(DUNE_FLAT_RADIUS, DUNE_FLAT_RADIUS + DUNE_RAMP, d)


# Fade the dunes down to zero as they approach the grid boundary.
func _dune_edge(x: float, z: float) -> float:
	var ex := smoothstep(DUNE_AREA, DUNE_AREA - DUNE_EDGE_FADE, absf(x))
	var ez := smoothstep(DUNE_AREA, DUNE_AREA - DUNE_EDGE_FADE, absf(z))
	return ex * ez


# Build the dune surface as a single mesh and hide the flat sand box's
# visual (its collision stays: the player never leaves the flat path).
func _build_dunes() -> void:
	var box_mesh: BoxMesh = $Sand/MeshInstance3D.mesh
	var dune_mat: StandardMaterial3D = box_mesh.material.duplicate()
	# Double-sided so the sheet is visible regardless of triangle winding;
	# the analytic normals below keep the lighting correct either way.
	dune_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	$Sand/MeshInstance3D.visible = false

	var steps := int(2.0 * DUNE_AREA / DUNE_CELL)
	var e := DUNE_CELL * 0.5
	var positions: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	for j in steps + 1:
		var z := -DUNE_AREA + float(j) * DUNE_CELL
		var row_p := PackedVector3Array()
		var row_n := PackedVector3Array()
		for i in steps + 1:
			var x := -DUNE_AREA + float(i) * DUNE_CELL
			var h := _dune_height(x, z)
			var hx := _dune_height(x + e, z) - _dune_height(x - e, z)
			var hz := _dune_height(x, z + e) - _dune_height(x, z - e)
			row_p.append(Vector3(x, h, z))
			row_n.append(Vector3(-hx, 2.0 * e, -hz).normalized())
		positions.append(row_p)
		normals.append(row_n)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in steps:
		for i in steps:
			_dune_quad(st, positions, normals, i, j)
	var mesh := st.commit()

	var mi := MeshInstance3D.new()
	mi.name = "Dunes"
	mi.mesh = mesh
	mi.material_override = dune_mat
	add_child(mi)


func _dune_quad(st: SurfaceTool, pos: Array[PackedVector3Array],
		nrm: Array[PackedVector3Array], i: int, j: int) -> void:
	# Two triangles per cell, wound so the lit face points up.
	_dune_vertex(st, pos, nrm, i, j)
	_dune_vertex(st, pos, nrm, i, j + 1)
	_dune_vertex(st, pos, nrm, i + 1, j)
	_dune_vertex(st, pos, nrm, i + 1, j)
	_dune_vertex(st, pos, nrm, i, j + 1)
	_dune_vertex(st, pos, nrm, i + 1, j + 1)


func _dune_vertex(st: SurfaceTool, pos: Array[PackedVector3Array],
		nrm: Array[PackedVector3Array], i: int, j: int) -> void:
	st.set_normal(nrm[j][i])
	st.add_vertex(pos[j][i])


# Scatter angular boulders across the dunes, well clear of the path.
func _build_rocks() -> void:
	for i in ROCK_COUNT:
		var z := lerpf(START_Z - 6.0, END_Z + 10.0, float(i) / float(ROCK_COUNT - 1))
		var side := 1.0 if i % 2 == 0 else -1.0
		var lateral := 8.0 + _hash01(i * 3 + 1) * 12.0
		var x := _path_x(clampf(z, END_Z, START_Z)) + side * lateral
		var s := 0.5 + _hash01(i * 7 + 2) * 1.5
		var rock := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(s, s * 0.7, s * 0.9)
		rock.mesh = bm
		rock.material_override = SANDSTONE_MATERIAL
		rock.position = Vector3(x, _dune_height(x, z) - s * 0.2, z)
		rock.rotation = Vector3(
			(_hash01(i) - 0.5) * 0.5,
			_hash01(i * 5 + 4) * TAU,
			(_hash01(i * 11 + 6) - 0.5) * 0.5)
		add_child(rock)


func _hash01(n: int) -> float:
	var v := sin(float(n) * 127.1 + 11.7) * 43758.5453
	return v - floor(v)


func _physics_process(delta: float) -> void:
	if GameManager.touch_mode:
		_drive_auto_run(delta)

	var p := player.global_position
	var closest := track.curve.get_closest_point(Vector3(p.x, 0.0, p.z))
	var offset := Vector2(p.x - closest.x, p.z - closest.z)

	if offset.length() > PATH_HALF_WIDTH:
		var limited := offset.limit_length(PATH_HALF_WIDTH)
		player.global_position.x = closest.x + limited.x
		player.global_position.z = closest.z + limited.y


func _restart_spear_timer() -> void:
	_spear_timer.start(randf_range(SPEAR_MIN_INTERVAL, SPEAR_MAX_INTERVAL))


# Only one spear may be on screen at a time: a low and a high spear
# together would be impossible to dodge.
func _on_spear_timer_timeout() -> void:
	if player.global_position.z < RANDOM_SPEARS_START_Z \
			and player.global_position.z > SPEAR_SHELTER_Z \
			and not spear_layer.has_active_spears():
		spear_layer.spawn_spear(randf() < 0.5, randf() < 0.5)
	_restart_spear_timer()


func _on_practice_timer_timeout() -> void:
	# After the long lead-in, drop back to the regular practice cadence.
	_practice_timer.wait_time = PRACTICE_INTERVAL
	if spear_layer.has_active_spears():
		return
	if player.global_position.z <= SPEAR_SHELTER_Z:
		return
	spear_layer.spawn_spear(_practice_high, _practice_high)
	_practice_high = not _practice_high


func _on_god_mode_changed(enabled: bool) -> void:
	god_label.visible = enabled


func _on_player_respawned() -> void:
	spear_layer._clear_spears()
	spear_layer.reset_ramp()
	_practice_high = false
	_practice_timer.wait_time = INITIAL_SPEAR_DELAY
	_practice_timer.start()
	_restart_spear_timer()


func _on_player_hit(hit_high: bool) -> void:
	if GameManager.god_mode:
		return
	player.die_and_reset(_spawn_transform, hit_high)

