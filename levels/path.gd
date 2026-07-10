extends Node3D

const PATH_HALF_WIDTH: float = 1.5
const START_Z: float = 20.0
const END_Z: float = -25.0
const AMPLITUDE: float = 3.0
const WAVELENGTH: float = 15.0
const SAMPLE_STEP: float = 1.0

@onready var player: CharacterBody3D = $Player
@onready var track: Path3D = $Track


func _ready() -> void:
	track.curve = _build_curve()


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
