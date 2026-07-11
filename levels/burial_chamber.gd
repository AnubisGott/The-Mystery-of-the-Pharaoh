extends Node3D

# Level 4: The Burial Chamber. The player lights the two fire bowls
# flanking the locked door (F/E) to open it, then finds the burial
# chamber: the sarcophagus of Tut-Ench-Amun, an Anubis statue and two
# hieroglyph dials beside the pit strip. Turning both dials at least
# once opens the floor — the player falls through, and the level ends.

const LEVEL_MUSIC: AudioStream = preload("res://soundAndMusic/music/AztekenherausforderungLevel04.mp3")
const WALL_MATERIAL: StandardMaterial3D = preload("res://materials/sandstone_sphinx.tres")
const FLOOR_MATERIAL: StandardMaterial3D = preload("res://materials/sandstone_pyramid.tres")
const Torch := preload("res://levels/torch.gd")
const FireBowl := preload("res://levels/fire_bowl.gd")
const GlyphDial := preload("res://levels/glyph_dial.gd")
const IntroTitle := preload("res://ui/intro_title.gd")

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
var _pit_slabs: Array[AnimatableBody3D] = []
var _turned_count: int = 0
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


func _physics_process(_delta: float) -> void:
	if _intro_running:
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
		prompt_label.text = "F / E - %s" % best.prompt
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
	var gold_trim := StandardMaterial3D.new()
	gold_trim.albedo_color = Color(0.8, 0.62, 0.25)
	gold_trim.metallic = 0.5
	gold_trim.roughness = 0.4
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
	var door_glyph := Glyphs.build(0, 0.8)
	door_glyph.position = Vector3(0, 0.4, 0.25)
	_door.add_child(door_glyph)
	_door.position = Vector3(0, 1.8, -8)
	add_child(_door)

	# Chamber shell (x -7..7, z -8..-22).
	_add_box(Vector3(-7.2, 2.75, -15), Vector3(0.4, 5.5, 14), WALL_MATERIAL)
	_add_box(Vector3(7.2, 2.75, -15), Vector3(0.4, 5.5, 14), WALL_MATERIAL)
	_add_box(Vector3(0, 2.75, -22.2), Vector3(14.8, 5.5, 0.4), WALL_MATERIAL)
	_add_box(Vector3(0, 5.7, -15), Vector3(14.8, 0.4, 14.8), WALL_MATERIAL)

	# Chamber floor: entry strip, the openable pit strip, back section.
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

	# The pit below the openable strip.
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

	# Dais and the upright sarcophagus with the death mask.
	_add_box(Vector3(0, 0.25, -18.5), Vector3(4, 0.5, 2.6), FLOOR_MATERIAL)
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.85, 0.66, 0.22)
	gold.metallic = 0.7
	gold.roughness = 0.3
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color(0.12, 0.25, 0.55)
	blue.roughness = 0.5
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.07, 0.06)

	var coffin := Node3D.new()
	coffin.position = Vector3(0, 0.5, -19.0)
	add_child(coffin)
	_prop_box(coffin, gold, Vector3(1.3, 2.7, 0.75), Vector3(0, 1.35, 0))
	# Death mask: face plate, eyes, royal beard and nemes stripes.
	_prop_box(coffin, gold, Vector3(0.85, 0.9, 0.12), Vector3(0, 1.95, 0.42))
	_prop_box(coffin, dark, Vector3(0.16, 0.07, 0.03), Vector3(-0.2, 2.12, 0.5))
	_prop_box(coffin, dark, Vector3(0.16, 0.07, 0.03), Vector3(0.2, 2.12, 0.5))
	_prop_box(coffin, gold, Vector3(0.12, 0.34, 0.1), Vector3(0, 1.6, 0.46))
	for i in 3:
		_prop_box(coffin, blue, Vector3(1.34, 0.14, 0.79),
				Vector3(0, 2.52 - i * 0.28, 0))
	_prop_box(coffin, blue, Vector3(0.3, 0.75, 0.14), Vector3(-0.62, 1.85, 0.36))
	_prop_box(coffin, blue, Vector3(0.3, 0.75, 0.14), Vector3(0.62, 1.85, 0.36))

	# Anubis statue.
	var anubis := Node3D.new()
	anubis.position = Vector3(-4.8, 0, -19.5)
	add_child(anubis)
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.05, 0.05, 0.06)
	black.roughness = 0.4
	black.metallic = 0.2
	_prop_box(anubis, FLOOR_MATERIAL, Vector3(1.5, 0.5, 1.5), Vector3(0, 0.25, 0))
	_prop_box(anubis, black, Vector3(0.85, 1.7, 0.6), Vector3(0, 1.35, 0))
	_prop_box(anubis, gold, Vector3(0.9, 0.16, 0.65), Vector3(0, 2.1, 0))
	_prop_box(anubis, black, Vector3(0.5, 0.45, 0.55), Vector3(0, 2.45, 0.05))
	_prop_box(anubis, black, Vector3(0.16, 0.14, 0.45), Vector3(0, 2.4, 0.42))
	_prop_box(anubis, black, Vector3(0.14, 0.55, 0.08), Vector3(-0.16, 2.85, -0.1))
	_prop_box(anubis, black, Vector3(0.14, 0.55, 0.08), Vector3(0.16, 2.85, -0.1))

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
		dial.turned.connect(_on_dial_turned)
		_dials.append(dial)

	var glyph_walls: Array = [
		[Vector3(-6.9, 3.2, -12.0), -PI / 2.0, 0],
		[Vector3(6.9, 3.2, -12.0), PI / 2.0, 1],
		[Vector3(4.5, 3.4, -21.9), 0.0, 2],
		[Vector3(-1.9, 3.1, -7.7), 0.0, 1],
		[Vector3(1.9, 3.1, -7.7), 0.0, 2],
	]
	for data: Array in glyph_walls:
		var glyph := Glyphs.build(data[2], 1.1)
		glyph.position = data[0]
		glyph.rotation.y = data[1]
		add_child(glyph)


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


func _on_dial_turned() -> void:
	_turned_count += 1
	if _turned_count >= _dials.size():
		_open_floor()


func _open_floor() -> void:
	if floor_open:
		return
	floor_open = true
	# A moment of silence, then the floor slides away under the player —
	# and the dial sockets, standing on those slabs, tumble into the pit.
	var tween := create_tween()
	tween.tween_interval(0.8)
	tween.tween_property(_pit_slabs[0], "position:x", -10.6, 1.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(_pit_slabs[1], "position:x", 10.6, 1.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	for i in _dials.size():
		var dial: Node3D = _dials[i]
		tween.parallel().tween_property(dial, "position:y", dial.position.y - 12.0, 1.3) \
				.set_delay(0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(dial, "rotation:x", 0.9 - 0.4 * i, 1.3) \
				.set_delay(0.5)


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
	title.setup("Level 4", "The Burial Chamber")
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
