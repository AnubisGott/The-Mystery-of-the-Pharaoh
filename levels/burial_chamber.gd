extends Node3D

# Level 4: The Burial Chamber. The player lights the two fire bowls
# flanking the locked door (F/E) to open it, then finds the burial
# chamber: the sarcophagus of Tut-Ench-Amun, an Anubis statue and two
# hieroglyph dials beside the pit strip. Each dial carries four
# symbols; when both dials show their wall glyph at the same time the
# floor opens — the player falls through, and the level ends.

const LEVEL_MUSIC: AudioStream = preload("res://soundAndMusic/music/AztekenherausforderungLevel04.mp3")
const WALL_MATERIAL: StandardMaterial3D = preload("res://materials/sandstone_sphinx.tres")
const FLOOR_MATERIAL: StandardMaterial3D = preload("res://materials/sandstone_pyramid.tres")
const Torch := preload("res://levels/torch.gd")
const FireBowl := preload("res://levels/fire_bowl.gd")
const GlyphDial := preload("res://levels/glyph_dial.gd")
const IntroTitle := preload("res://ui/intro_title.gd")
const SARCOPHAGUS: PackedScene = preload("res://models/sarcophagus.glb")
const ANUBIS: PackedScene = preload("res://models/anubis.glb")
const CAT: PackedScene = preload("res://models/cat.glb")
const RUMBLE_SOUND: AudioStream = preload("res://sounds/stone_rumble.wav")

const INTRO_HOLD: float = 1.4
const INTERACT_RANGE: float = 1.7

# Chamber frame: antechamber (8 wide) in front of the burial chamber
# (14 wide); the pit strip of the chamber floor slides open at the end.
const PIT_FROM_Z: float = -10.0
const PIT_TO_Z: float = -14.5

@onready var player: CharacterBody3D = $Player
@onready var god_label: Label = $ControlsHint/Root/GodLabel
@onready var prompt_label: Label = $ControlsHint/Root/PromptLabel

# The pre-play cinematic; disabled for headless runs (tests).
@export var intro_enabled: bool = true

var door_open: bool = false
var floor_open: bool = false

var _spawn_transform: Transform3D
var _door: AnimatableBody3D
var _bowls: Array[Node3D] = []
var _dials: Array[Node3D] = []
var _dial_blockers: Array[Node3D] = []
var _pit_slabs: Array[AnimatableBody3D] = []
var _pulling: bool = false
var _intro_running: bool = false
var _intro_skip: bool = false
var _intro_can_skip: bool = false


func _ready() -> void:
	_spawn_transform = player.global_transform
	GameManager.play_music(LEVEL_MUSIC)
	_build_environment()
	_build_rooms()
	_build_furniture()

	god_label.visible = GameManager.god_mode
	GameManager.god_mode_changed.connect(_on_god_mode_changed)

	if intro_enabled and DisplayServer.get_name() != "headless":
		_play_intro()


func _physics_process(delta: float) -> void:
	if _intro_running:
		return
	# The falling-down sound as the player drops into the pit (the
	# player's own whistle logic may be off during the pull).
	if floor_open and player._whistle_player != null \
			and not player._whistle_played \
			and to_local(player.global_position).y < -1.0:
		player._whistle_player.play()
		player._whistle_played = true
	if _pulling:
		# Walk the stunned player into the open pit, wherever they
		# stand. The pull stays active until the level ends: the
		# player's own physics is off, so this loop is also what keeps
		# gravity flowing — cutting it early froze the player mid-air
		# and the next level never came.
		var target := to_global(Vector3(0, 0, (PIT_FROM_Z + PIT_TO_Z) / 2.0))
		var direction := target - player.global_position
		direction.y = 0.0
		var v := player.velocity
		if direction.length() > 0.4:
			var flat := direction.normalized() * 4.5
			v.x = flat.x
			v.z = flat.z
		else:
			v.x = 0.0
			v.z = 0.0
		if not player.is_on_floor():
			v.y -= 9.8 * delta
		player.velocity = v
		player.move_and_slide()
		return
	var best: Node3D = null
	var best_distance := INTERACT_RANGE
	for node in get_tree().get_nodes_in_group("interactables"):
		if not is_ancestor_of(node) or not node.can_interact():
			continue
		var distance: float = player.global_position.distance_to(
				node.global_position + Vector3.UP * 1.2)
		if distance < best_distance:
			best_distance = distance
			best = node
	prompt_label.visible = best != null
	if best != null:
		prompt_label.text = tr("E or F - %s") % tr(best.prompt)
		if Input.is_action_just_pressed("interact"):
			best.interact()


func _unhandled_input(event: InputEvent) -> void:
	# Skip the intro on a fresh key or click - but not on key repeats
	# or input left over from finishing the previous level (a short
	# grace period swallows those).
	if _intro_running and _intro_can_skip and event.is_pressed() \
			and not event.is_echo() \
			and (event is InputEventKey or event is InputEventMouseButton):
		_intro_skip = true


# ---------------------------------------------------------------- rooms

func _build_rooms() -> void:
	# Antechamber floor and shell (x -4..4, z +1..-8).
	_add_box(Vector3(0, -0.2, -3.5), Vector3(8, 0.4, 9), FLOOR_MATERIAL)
	_add_box(Vector3(-4.2, 2.1, -3.5), Vector3(0.4, 4.6, 9), WALL_MATERIAL)
	_add_box(Vector3(4.2, 2.1, -3.5), Vector3(0.4, 4.6, 9), WALL_MATERIAL)
	_add_box(Vector3(0, 2.1, 1.2), Vector3(8.8, 4.6, 0.4), WALL_MATERIAL)
	_add_box(Vector3(0, 4.4, -3.5), Vector3(8.8, 0.4, 9.4), WALL_MATERIAL)

	# Chamber front wall with the doorway (x -7..7 at z=-8).
	_add_box(Vector3(-4.25, 2.75, -8), Vector3(5.5, 5.5, 0.5), WALL_MATERIAL)
	_add_box(Vector3(4.25, 2.75, -8), Vector3(5.5, 5.5, 0.5), WALL_MATERIAL)
	_add_box(Vector3(0, 4.55, -8), Vector3(3.0, 1.9, 0.5), WALL_MATERIAL)

	# The sinking door slab.
	_door = AnimatableBody3D.new()
	var door_collision := CollisionShape3D.new()
	var door_shape := BoxShape3D.new()
	door_shape.size = Vector3(3.0, 3.6, 0.45)
	door_collision.shape = door_shape
	_door.add_child(door_collision)
	var door_mesh := MeshInstance3D.new()
	var door_box := BoxMesh.new()
	door_box.size = Vector3(3.0, 3.6, 0.45)
	door_box.material = FLOOR_MATERIAL
	door_mesh.mesh = door_box
	_door.add_child(door_mesh)
	_door.position = Vector3(0, 1.8, -8)
	add_child(_door)

	# Chamber shell (x -7..7, z -8..-22).
	_add_box(Vector3(-7.2, 2.75, -15), Vector3(0.4, 5.5, 14), WALL_MATERIAL)
	_add_box(Vector3(7.2, 2.75, -15), Vector3(0.4, 5.5, 14), WALL_MATERIAL)
	_add_box(Vector3(0, 2.75, -22.2), Vector3(14.8, 5.5, 0.4), WALL_MATERIAL)
	_add_box(Vector3(0, 5.7, -15), Vector3(14.8, 0.4, 14.8), WALL_MATERIAL)

	# Chamber floor: entry strip, the droppable pit strip, back section.
	_add_box(Vector3(0, -0.2, -9.0), Vector3(14, 0.4, 2.0), FLOOR_MATERIAL)
	_add_box(Vector3(0, -0.2, -18.25), Vector3(14, 0.4, 7.5), FLOOR_MATERIAL)
	for side: float in [-1.0, 1.0]:
		var slab := AnimatableBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(7, 0.4, PIT_FROM_Z - PIT_TO_Z)
		collision.shape = shape
		slab.add_child(collision)
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(7, 0.4, PIT_FROM_Z - PIT_TO_Z)
		box.material = FLOOR_MATERIAL
		mesh.mesh = box
		slab.add_child(mesh)
		slab.position = Vector3(side * 3.5, -0.2, (PIT_FROM_Z + PIT_TO_Z) / 2.0)
		add_child(slab)
		_pit_slabs.append(slab)

	# The pit shaft below the droppable strip.
	var pit_mid_z := (PIT_FROM_Z + PIT_TO_Z) / 2.0
	_add_box(Vector3(-7.0, -6.2, pit_mid_z), Vector3(0.4, 12, 4.5), WALL_MATERIAL)
	_add_box(Vector3(7.0, -6.2, pit_mid_z), Vector3(0.4, 12, 4.5), WALL_MATERIAL)
	_add_box(Vector3(0, -6.2, PIT_FROM_Z + 0.2), Vector3(14, 12, 0.4), WALL_MATERIAL)
	_add_box(Vector3(0, -6.2, PIT_TO_Z - 0.2), Vector3(14, 12, 0.4), WALL_MATERIAL)

	# Torches.
	for data: Array in [[-3.9, -4.0, 1.0], [3.9, -4.0, -1.0],
			[-6.9, -11.0, 1.0], [6.9, -11.0, -1.0],
			[-6.9, -18.5, 1.0], [6.9, -18.5, -1.0]]:
		var torch := Torch.new()
		torch.basis = Basis.looking_at(Vector3(data[2], 0, 0))
		torch.position = Vector3(data[0], 2.4, data[1])
		add_child(torch)


func _build_furniture() -> void:
	# Fire bowls flanking the door.
	for side: float in [-1.0, 1.0]:
		var bowl := FireBowl.new()
		bowl.position = Vector3(side * 2.6, 0, -6.6)
		add_child(bowl)
		bowl.lit_changed.connect(_on_bowl_lit)
		_bowls.append(bowl)
		_add_blocker(Vector3(side * 2.6, 0.55, -6.6), Vector3(0.8, 1.1, 0.8))

	# Dais and the upright sarcophagus of Tut-Ench-Amun — a painted
	# museum scan (CC-BY, see models/CREDITS.md); they stand clear of
	# the pit and stay through the finale.
	_add_box(Vector3(0, 0.25, -18.5), Vector3(4, 0.5, 2.6), FLOOR_MATERIAL)

	var coffin: Node3D = SARCOPHAGUS.instantiate()
	coffin.position = Vector3(0, 0.5, -19.0)
	add_child(coffin)
	_add_blocker(Vector3(0, 2.1, -19.0), Vector3(1.1, 3.2, 0.9))

	# Anubis statue — the jackal on its own gold pedestal, lofted from
	# the four-view artwork (tools/blender/make_anubis.py).
	var anubis: Node3D = ANUBIS.instantiate()
	anubis.position = Vector3(-4.8, 0, -19.5)
	add_child(anubis)
	_add_blocker(Vector3(-4.8, 1.3, -19.5), Vector3(1.7, 2.6, 2.3))

	# The Bastet cat guards the other flank on a plain stone dais like
	# the sarcophagus's.
	_add_box(Vector3(4.8, 0.25, -19.5), Vector3(2.2, 0.5, 2.2), FLOOR_MATERIAL)
	var cat: Node3D = CAT.instantiate()
	cat.position = Vector3(4.8, 0.5, -19.5)
	add_child(cat)
	_add_blocker(Vector3(4.8, 1.5, -19.5), Vector3(0.9, 2.0, 1.5))

	# The two dials flanking the pit strip, and the wall glyphs.
	var dial_data: Array = [
		[Vector3(-5.9, 0, -12.0), -PI / 2.0, 0],
		[Vector3(5.9, 0, -12.0), PI / 2.0, 1],
	]
	for data: Array in dial_data:
		var dial := GlyphDial.new()
		dial.glyph_kind = data[2]
		dial.position = data[0]
		dial.rotation.y = data[1]
		add_child(dial)
		dial.solved.connect(_on_dial_solved)
		_dials.append(dial)
		var blocker := _make_blocker(Vector3(0, 0.8, 0), Vector3(0.9, 1.6, 0.9))
		dial.add_child(blocker)
		_dial_blockers.append(blocker)

	# The two puzzle glyphs (ankh and djed) above their dials and
	# flanking the door, plus the back-wall glyphs behind the statues:
	# the ankh behind the cat, the pyramid behind Anubis.
	var glyph_walls: Array = [
		[Vector3(-6.9, 3.2, -12.0), -PI / 2.0, 0],
		[Vector3(6.9, 3.2, -12.0), PI / 2.0, 1],
		[Vector3(-1.9, 3.1, -7.7), 0.0, 0],
		[Vector3(1.9, 3.1, -7.7), 0.0, 1],
		[Vector3(4.8, 3.1, -21.9), 0.0, 0],
		[Vector3(-4.8, 3.1, -21.9), 0.0, 3],
	]
	for data: Array in glyph_walls:
		var glyph := Glyphs.build(data[2], 1.1)
		glyph.position = data[0]
		glyph.rotation.y = data[1]
		add_child(glyph)


# Invisible collision so statues and furniture cannot be walked through.
func _make_blocker(center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.position = center
	return body


func _add_blocker(center: Vector3, size: Vector3) -> void:
	add_child(_make_blocker(center, size))


func _prop_box(parent: Node3D, material: Material, size: Vector3, pos: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	mesh.mesh = box
	mesh.position = pos
	parent.add_child(mesh)


func _add_box(center: Vector3, size: Vector3, material: Material) -> void:
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
	add_child(body)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.01, 0.008)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.4, 0.3)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.045, 0.03)
	env.fog_density = 0.02
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


# --------------------------------------------------------------- puzzle

func _on_bowl_lit() -> void:
	for bowl in _bowls:
		if not bowl.is_lit:
			return
	_open_door()


func _open_door() -> void:
	if door_open:
		return
	door_open = true
	var tween := create_tween()
	tween.tween_property(_door, "position:y", -1.85, 2.0) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_dial_solved() -> void:
	# Every dial must show its target at the same time.
	for dial in _dials:
		if not dial.is_solved:
			return
	_open_floor()


func _open_floor() -> void:
	if floor_open:
		return
	floor_open = true
	# The pit announces itself with a heavy stone rumble.
	var rumble := AudioStreamPlayer.new()
	rumble.stream = RUMBLE_SOUND
	rumble.bus = "Sfx"
	add_child(rumble)
	rumble.play()
	# A short beat, then the pit strip drops straight down like a
	# trapdoor. Dropping (instead of sliding sideways) matters: a
	# sideways-moving slab CARRIES whoever stands on it — that was the
	# "player gets beamed to the side" bug.
	var tween := create_tween()
	tween.tween_interval(0.4)
	tween.tween_property(_pit_slabs[0], "position:y", -14.2, 0.8) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(_pit_slabs[1], "position:y", -14.2, 0.8) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Once the trapdoor is gone, whoever still stands beside the pit is
	# dragged in — the fall comes no matter where the player was.
	tween.tween_callback(_start_pull)

	# The dial blockers must not ride along: fallen into the pit they
	# were invisible platforms that caught the player above the end zone.
	for blocker in _dial_blockers:
		blocker.queue_free()

	# The dial sockets ride the trapdoor down, toppling as they go;
	# Anubis and the sarcophagus stand clear of the pit and stay.
	var fall := create_tween()
	fall.set_parallel(true)
	for i in _dials.size():
		var dial: Node3D = _dials[i]
		fall.tween_property(dial, "position:y", dial.position.y - 14.0, 0.8) \
				.set_delay(0.45 + 0.1 * i).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		fall.tween_property(dial, "rotation:z", 0.5 - 1.0 * i, 0.8) \
				.set_delay(0.45 + 0.1 * i)


func _start_pull() -> void:
	# Solving the puzzle stuns the player: controls are off and the
	# pull owns the body until the level ends.
	_pulling = true
	player.set_physics_process(false)
	player.get_node("Visual/AnimationPlayer").play("Idle", 0.2)


func _on_god_mode_changed(enabled: bool) -> void:
	god_label.visible = enabled


# ---------------------------------------------------------------- intro

# A ~4 s cinematic: the camera drifts through the antechamber toward
# the sealed door and its cold fire bowls, zooming in and back out;
# mid-shot the frame freezes for the level title.
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
	title.setup(tr("Level %d") % 4, tr("The Burial Chamber"))
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
		cam.fov = 66.0 - 22.0 * sin(PI * t)
		cam.global_position = to_global(Vector3(
				2.6 - 2.0 * t, 1.9 - 0.3 * sin(PI * t), -0.8 - 2.8 * t))
		cam.look_at(to_global(Vector3(0, 1.7, -8)), Vector3.UP)
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
