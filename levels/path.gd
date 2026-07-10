extends Node3D

const SPEAR_SCENE: PackedScene = preload("res://hazards/spear.tscn")

const PATH_HALF_WIDTH: float = 1.5
const START_Z: float = 20.0
const END_Z: float = -25.0
const AMPLITUDE: float = 3.0
const WAVELENGTH: float = 15.0
const SAMPLE_STEP: float = 1.0

const SPEAR_MIN_INTERVAL: float = 1.6
const SPEAR_MAX_INTERVAL: float = 3.0
const SPEAR_SIDE_OFFSET: float = 13.0
const SPEAR_LOW_Y: float = 0.35
const SPEAR_HIGH_Y: float = 1.5

# Practice zone: two spears repeat at the same fixed spot near the
# start (low then high) so jump and duck can be tried safely. Random
# spears only begin past it.
const PRACTICE_Z: float = 13.0
const PRACTICE_INTERVAL: float = 2.4
const RANDOM_SPEARS_START_Z: float = 8.0

@onready var player: CharacterBody3D = $Player
@onready var track: Path3D = $Track

var _spawn_transform: Transform3D
var _spear_timer: Timer
var _practice_timer: Timer
var _practice_high: bool = false


func _ready() -> void:
	track.curve = _build_curve()
	_spawn_transform = player.global_transform

	_spear_timer = Timer.new()
	_spear_timer.one_shot = true
	_spear_timer.timeout.connect(_on_spear_timer_timeout)
	add_child(_spear_timer)
	_restart_spear_timer()

	_practice_timer = Timer.new()
	_practice_timer.wait_time = PRACTICE_INTERVAL
	_practice_timer.timeout.connect(_on_practice_timer_timeout)
	add_child(_practice_timer)
	_practice_timer.start()


func _build_curve() -> Curve3D:
	var curve := Curve3D.new()
	var z := START_Z
	while z >= END_Z - 0.01:
		curve.add_point(Vector3(_path_x(z), 0.0, z))
		z -= SAMPLE_STEP
	return curve


# The path winds left and right like a snake while heading forward.
func _path_x(z: float) -> float:
	return AMPLITUDE * sin(TAU * (START_Z - z) / WAVELENGTH)


func _physics_process(_delta: float) -> void:
	var p := player.global_position
	var closest := track.curve.get_closest_point(Vector3(p.x, 0.0, p.z))
	var offset := Vector2(p.x - closest.x, p.z - closest.z)

	if offset.length() > PATH_HALF_WIDTH:
		var limited := offset.limit_length(PATH_HALF_WIDTH)
		player.global_position.x = closest.x + limited.x
		player.global_position.z = closest.z + limited.y


func _restart_spear_timer() -> void:
	_spear_timer.start(randf_range(SPEAR_MIN_INTERVAL, SPEAR_MAX_INTERVAL))


func _on_spear_timer_timeout() -> void:
	if player.global_position.z < RANDOM_SPEARS_START_Z:
		_spawn_random_spear()
	_restart_spear_timer()


func _on_practice_timer_timeout() -> void:
	_spawn_spear_at(PRACTICE_Z, _practice_high, _practice_high)
	_practice_high = not _practice_high


# A spear crosses the path slightly ahead of the player, from a random
# side and at random height: low ones are jumped, high ones are ducked.
func _spawn_random_spear() -> void:
	var target_z: float = clamp(player.global_position.z - randf_range(3.0, 9.0), END_Z, START_Z)
	_spawn_spear_at(target_z, randf() < 0.5, randf() < 0.5)


func _spawn_spear_at(target_z: float, is_high: bool, from_left: bool) -> void:
	var spear := SPEAR_SCENE.instantiate()
	spear.direction = Vector3.RIGHT if from_left else Vector3.LEFT
	spear.position = Vector3(
		_path_x(target_z) + (-SPEAR_SIDE_OFFSET if from_left else SPEAR_SIDE_OFFSET),
		SPEAR_HIGH_Y if is_high else SPEAR_LOW_Y,
		target_z
	)
	spear.player_hit.connect(_on_player_hit)
	add_child(spear)


func _on_player_hit() -> void:
	player.reset_to_start(_spawn_transform)
