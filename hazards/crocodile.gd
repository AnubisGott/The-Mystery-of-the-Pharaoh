extends AnimatableBody3D

# A crocodile floating in the Nile, used as a stepping stone. Each one
# runs its own surface/sink cycle with a random phase and period; while
# it is under, whoever stood on it is in the water. The collision box
# is the croc's back, just above the waterline. The body is the
# generated low-poly model (tools/blender/make_crocodile.py); its
# separate "Eyes" mesh gets a per-croc material for the warning glow.

const CROC_SCENE: PackedScene = preload("res://models/crocodile.glb")

const SINK_DEPTH: float = 1.7
const SINK_TIME: float = 0.7
const UNDER_TIME: float = 1.4
# Shortly before diving the croc dips its snout and its eyes glow.
const WARN_TIME: float = 0.9
# How long each croc floats on the surface (rolled per croc).
const UP_TIME_MIN: float = 4.5
const UP_TIME_MAX: float = 7.0

# Set by the level before adding to the tree.
var surface_y: float = -0.15
var frozen: bool = false   # tests freeze the cycle

var _up_time: float = 4.0
var _time: float = 0.0
var _eye_material: StandardMaterial3D


func _ready() -> void:
	add_to_group("crocodiles")
	_up_time = randf_range(UP_TIME_MIN, UP_TIME_MAX)
	_time = randf() * cycle_length()
	sync_to_physics = false

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.95, 0.3, 2.4)
	collision.shape = shape
	add_child(collision)

	add_child(CROC_SCENE.instantiate())

	# The eyes get their own per-croc material so they can glow red as a
	# warning; the GLB keeps them as a separate "Eyes" mesh for this.
	for mesh in find_children("*", "MeshInstance3D", true, false):
		if String(mesh.name).begins_with("Eyes"):
			var eye_mesh := mesh as MeshInstance3D
			_eye_material = eye_mesh.get_active_material(0).duplicate()
			eye_mesh.set_surface_override_material(0, _eye_material)
			break


func cycle_length() -> float:
	return _up_time + SINK_TIME + UNDER_TIME + SINK_TIME


# Where the back will be `ahead` seconds from now. A hop is a second in
# the air, so Level 6 aims with this: a croc still climbing out of the
# water when the button is tapped is a landing spot by the time the feet
# come down.
func height_in(ahead: float) -> float:
	if frozen:
		return surface_y
	return surface_y + _offset_at(fmod(_time + ahead, cycle_length()))


# The back's height over its waterline at cycle time t.
func _offset_at(t: float) -> float:
	if t < _up_time:
		var offset := 0.04 * sin(TAU * t / 1.9)   # idle bobbing
		var warn := t - (_up_time - WARN_TIME)
		if warn > 0.0:
			# The dip of the tell before the dive. It ramps in gently — any
			# sudden or trembling platform motion makes is_on_floor()
			# flicker and eats the escape jump.
			offset -= 0.08 * minf(warn / 0.25, 1.0)
		return offset
	if t < _up_time + SINK_TIME:
		# Ease into the dive: the first tenths are slow, so a well-timed
		# jump still gets off the sinking back.
		var k := (t - _up_time) / SINK_TIME
		return -0.08 - (SINK_DEPTH - 0.08) * k * k
	if t < _up_time + SINK_TIME + UNDER_TIME:
		return -SINK_DEPTH
	return -SINK_DEPTH * (1.0 - (t - _up_time - SINK_TIME - UNDER_TIME) / SINK_TIME)


func _physics_process(delta: float) -> void:
	if frozen:
		position.y = surface_y
		return
	_time += delta
	var t := fmod(_time, cycle_length())
	var pitch := 0.0
	var warning := false
	if t < _up_time:
		var warn := t - (_up_time - WARN_TIME)
		if warn > 0.0:
			# The tell before the dive: a dipped snout and glowing red eyes.
			pitch = -0.1 * minf(warn / 0.25, 1.0)
			warning = true
	elif t < _up_time + SINK_TIME:
		pitch = -0.12
	position.y = surface_y + _offset_at(t)
	rotation.x = pitch
	if _eye_material.emission_enabled != warning:
		_eye_material.emission_enabled = warning
		_eye_material.emission = Color(1.0, 0.15, 0.05)
		_eye_material.emission_energy_multiplier = 2.5
