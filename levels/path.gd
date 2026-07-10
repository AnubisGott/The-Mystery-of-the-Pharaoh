extends Node3D

const PATH_HALF_WIDTH: float = 1.5
const START_Z: float = 30.0
const END_Z: float = -40.0
const AMPLITUDE: float = 3.0
const WAVELENGTH: float = 15.0
const SAMPLE_STEP: float = 1.0

# The path is straight before/after these, winding in between.
const WINDING_START_Z: float = 20.0
const WINDING_END_Z: float = -30.0
const WINDING_FADE: float = 6.0

const SPEAR_MIN_INTERVAL: float = 1.6
const SPEAR_MAX_INTERVAL: float = 3.0

# Practice near the start: spears alternate low (jump) and high (duck)
# in a fixed rhythm. Random spears only begin past the practice zone.
const PRACTICE_INTERVAL: float = 2.4
const RANDOM_SPEARS_START_Z: float = 18.0

@onready var player: CharacterBody3D = $Player
@onready var track: Path3D = $Track
@onready var spear_layer: CanvasLayer = $SpearLayer

var _spawn_transform: Transform3D
var _spear_timer: Timer
var _practice_timer: Timer
var _practice_high: bool = false


func _ready() -> void:
	track.curve = _build_curve()
	_spawn_transform = player.global_transform
	spear_layer.player_hit.connect(_on_player_hit)

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


# Only one spear may be on screen at a time: a low and a high spear
# together would be impossible to dodge.
func _on_spear_timer_timeout() -> void:
	if player.global_position.z < RANDOM_SPEARS_START_Z and not spear_layer.has_active_spears():
		spear_layer.spawn_spear(randf() < 0.5, randf() < 0.5)
	_restart_spear_timer()


func _on_practice_timer_timeout() -> void:
	if spear_layer.has_active_spears():
		return
	spear_layer.spawn_spear(_practice_high, _practice_high)
	_practice_high = not _practice_high


func _on_player_hit() -> void:
	player.reset_to_start(_spawn_transform)
