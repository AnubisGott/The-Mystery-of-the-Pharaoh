extends Node3D

# A wall torch for the pendulum hall: iron mount plate, tilted wooden
# handle held by a ring, a coal cup, and a layered flame — emissive
# core, rising fire particles and a flickering light. Everything is
# built procedurally like the rest of the hall. Local -Z faces into
# the room (set the basis with Basis.looking_at(inward)).

const LIGHT_COLOR := Color(1.0, 0.62, 0.28)
const LIGHT_ENERGY: float = 2.2

var _light: OmniLight3D
var _core: MeshInstance3D
var _time: float = 0.0
var _phase: float = 0.0


func _ready() -> void:
	_phase = randf() * TAU
	_build_bracket()
	_build_flame()


func _process(delta: float) -> void:
	# Two incommensurate sines per property give an organic flicker;
	# the per-torch phase keeps neighbouring torches out of sync.
	_time += delta
	var flick := 1.0 + 0.10 * sin(_time * 9.7 + _phase) \
			+ 0.06 * sin(_time * 23.3 + _phase * 1.7)
	_light.light_energy = LIGHT_ENERGY * flick
	_core.scale = Vector3(
		1.0 + 0.08 * sin(_time * 15.9 + _phase * 2.0),
		1.0 + 0.18 * sin(_time * 11.3 + _phase),
		1.0 + 0.08 * cos(_time * 14.1 + _phase))


func _build_bracket() -> void:
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.16, 0.14, 0.13)
	iron.roughness = 0.9

	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.30, 0.20, 0.11)
	wood.roughness = 1.0

	var plate := MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(0.16, 0.24, 0.04)
	plate_mesh.material = iron
	plate.mesh = plate_mesh
	plate.position = Vector3(0, 0.12, -0.02)
	add_child(plate)

	# Handle tilted so its top leans into the room; the cup sits on it.
	var handle := MeshInstance3D.new()
	var handle_mesh := CylinderMesh.new()
	handle_mesh.top_radius = 0.028
	handle_mesh.bottom_radius = 0.022
	handle_mesh.height = 0.55
	handle_mesh.material = wood
	handle.mesh = handle_mesh
	handle.rotation.x = -0.42
	handle.position = Vector3(0, 0.24, -0.12)
	add_child(handle)

	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.03
	ring_mesh.outer_radius = 0.055
	ring_mesh.material = iron
	ring.mesh = ring_mesh
	ring.rotation.x = -0.42
	ring.position = Vector3(0, 0.20, -0.10)
	add_child(ring)

	# The cup gets a warmer, lighter iron so the lit torch reads as one
	# connected piece instead of a floating flame.
	var cup_iron := StandardMaterial3D.new()
	cup_iron.albedo_color = Color(0.28, 0.22, 0.17)
	cup_iron.roughness = 0.85

	var cup := MeshInstance3D.new()
	var cup_mesh := CylinderMesh.new()
	cup_mesh.top_radius = 0.06
	cup_mesh.bottom_radius = 0.03
	cup_mesh.height = 0.10
	cup_mesh.material = cup_iron
	cup.mesh = cup_mesh
	cup.position = Vector3(0, 0.50, -0.235)
	add_child(cup)


func _build_flame() -> void:
	var coal := StandardMaterial3D.new()
	coal.albedo_color = Color(0.5, 0.15, 0.03)
	coal.emission_enabled = true
	coal.emission = Color(1.0, 0.35, 0.05)
	coal.emission_energy_multiplier = 1.6

	var coals := MeshInstance3D.new()
	var coals_mesh := SphereMesh.new()
	coals_mesh.radius = 0.055
	coals_mesh.height = 0.07
	coals_mesh.material = coal
	coals.mesh = coals_mesh
	coals.position = Vector3(0, 0.555, -0.235)
	add_child(coals)

	# Kept dim enough that the glow pass does not blow it out into a
	# white blob; the particles carry the flame shape.
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(1.0, 0.75, 0.3)
	core_mat.emission_enabled = true
	core_mat.emission = Color(1.0, 0.58, 0.1)
	core_mat.emission_energy_multiplier = 2.2

	_core = MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.04
	core_mesh.height = 0.15
	core_mesh.material = core_mat
	_core.mesh = core_mesh
	_core.position = Vector3(0, 0.61, -0.235)
	add_child(_core)

	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	var particle_mat := StandardMaterial3D.new()
	particle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	particle_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_mat.vertex_color_use_as_albedo = true
	particle_mat.disable_receive_shadows = true
	quad.material = particle_mat

	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 1.0))
	fade.add_point(Vector2(1.0, 0.1))

	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.9, 0.45, 0.9))
	ramp.set_color(1, Color(0.4, 0.08, 0.02, 0.0))
	ramp.add_point(0.45, Color(1.0, 0.45, 0.1, 0.75))

	var particles := CPUParticles3D.new()
	particles.mesh = quad
	particles.amount = 16
	particles.lifetime = 0.7
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.035
	particles.direction = Vector3.UP
	particles.spread = 12.0
	particles.gravity = Vector3.ZERO
	particles.initial_velocity_min = 0.4
	particles.initial_velocity_max = 0.9
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.0
	particles.scale_amount_curve = fade
	particles.color_ramp = ramp
	particles.position = Vector3(0, 0.60, -0.235)
	add_child(particles)

	_light = OmniLight3D.new()
	_light.light_color = LIGHT_COLOR
	_light.light_energy = LIGHT_ENERGY
	_light.omni_range = 9.0
	_light.position = Vector3(0, 0.65, -0.32)
	add_child(_light)
