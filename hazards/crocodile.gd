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


func _physics_process(delta: float) -> void:
	if frozen:
		position.y = surface_y
		return
	_time += delta
	var t := fmod(_time, cycle_length())
	var offset := 0.0
	var pitch := 0.0
	var warning := false
	if t < _up_time:
		offset = 0.04 * sin(TAU * t / 1.9)   # idle bobbing
		var warn := t - (_up_time - WARN_TIME)
		if warn > 0.0:
			# The tell before the dive: a dipped snout and glowing red
			# eyes. The dip ramps in gently — any sudden or trembling
			# platform motion makes is_on_floor() flicker and eats the
			# escape jump.
			offset -= 0.08 * minf(warn / 0.25, 1.0)
			pitch = -0.1 * minf(warn / 0.25, 1.0)
			warning = true
	elif t < _up_time + SINK_TIME:
		# Ease into the dive: the first tenths are slow, so a well-timed
		# jump still gets off the sinking back.
		var k := (t - _up_time) / SINK_TIME
		offset = -0.08 - (SINK_DEPTH - 0.08) * k * k
		pitch = -0.12
	elif t < _up_time + SINK_TIME + UNDER_TIME:
		offset = -SINK_DEPTH
	else:
		offset = -SINK_DEPTH * (1.0 - (t - _up_time - SINK_TIME - UNDER_TIME) / SINK_TIME)
	position.y = surface_y + offset
	rotation.x = pitch
	if _eye_material.emission_enabled != warning:
		_eye_material.emission_enabled = warning
		_eye_material.emission = Color(1.0, 0.15, 0.05)
		_eye_material.emission_energy_multiplier = 2.5
