extends AnimatableBody3D

# A crocodile floating in the Nile, used as a stepping stone. Each one
# runs its own surface/sink cycle with a random phase and period; while
# it is under, whoever stood on it is in the water. The collision box
# is the croc's back, just above the waterline.

const SINK_DEPTH: float = 1.7
const SINK_TIME: float = 0.7
const UNDER_TIME: float = 2.2
# Shortly before diving the croc trembles and dips its snout.
const WARN_TIME: float = 0.9

# Set by the level before adding to the tree.
var surface_y: float = -0.15
var frozen: bool = false   # tests freeze the cycle

var _up_time: float = 4.0
var _time: float = 0.0
var _eye_material: StandardMaterial3D


func _ready() -> void:
	add_to_group("crocodiles")
	_up_time = randf_range(3.2, 5.4)
	_time = randf() * cycle_length()
	sync_to_physics = false

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.95, 0.3, 2.4)
	collision.shape = shape
	add_child(collision)

	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.2, 0.34, 0.16)
	green.roughness = 0.9
	var belly := StandardMaterial3D.new()
	belly.albedo_color = Color(0.35, 0.4, 0.25)
	belly.roughness = 0.9
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.14, 0.07)

	_mesh_box(green, Vector3(0.95, 0.4, 2.0), Vector3(0, -0.05, 0.1))
	_mesh_box(belly, Vector3(0.6, 0.28, 0.85), Vector3(0, 0.0, -1.25))
	_mesh_box(green, Vector3(0.45, 0.22, 1.1), Vector3(0, -0.1, 1.6))
	for i in 3:
		_mesh_box(dark, Vector3(0.12, 0.12, 0.5), Vector3(0, 0.18, -0.4 + i * 0.6))
	# The eyes get their own material so they can glow red as a warning.
	_eye_material = StandardMaterial3D.new()
	_eye_material.albedo_color = Color(0.1, 0.14, 0.07)
	_mesh_box(_eye_material, Vector3(0.1, 0.12, 0.1), Vector3(-0.22, 0.18, -1.05))
	_mesh_box(_eye_material, Vector3(0.1, 0.12, 0.1), Vector3(0.22, 0.18, -1.05))


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
			# The tell before the dive: a steady dipped snout and glowing
			# red eyes. Steady on purpose — a trembling platform makes
			# is_on_floor() flicker and eats the escape jump.
			offset -= 0.08
			pitch = -0.1
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


func _mesh_box(material: Material, size: Vector3, pos: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	mesh.mesh = box
	mesh.position = pos
	add_child(mesh)
