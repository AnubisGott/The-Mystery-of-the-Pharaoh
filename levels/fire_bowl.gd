extends Node3D

# A standing fire bowl beside the burial-chamber door. Starts cold;
# light() ignites it: glowing coals, an emissive flame core, rising
# fire particles and a flickering light — the torch recipe on a
# pedestal. Interactable via the level's prompt system.

signal lit_changed

var prompt: String = "Light the fire bowl"
var is_lit: bool = false

var _coals: MeshInstance3D
var _light: OmniLight3D
var _core: MeshInstance3D
var _time: float = 0.0
var _phase: float = 0.0


func _ready() -> void:
	add_to_group("interactables")
	_phase = randf() * TAU

	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.45, 0.38, 0.3)
	stone.roughness = 0.95

	var pedestal := MeshInstance3D.new()
	var pedestal_mesh := CylinderMesh.new()
	pedestal_mesh.top_radius = 0.2
	pedestal_mesh.bottom_radius = 0.3
	pedestal_mesh.height = 1.0
	pedestal_mesh.material = stone
	pedestal.mesh = pedestal_mesh
	pedestal.position = Vector3(0, 0.5, 0)
	add_child(pedestal)

	var bowl := MeshInstance3D.new()
	var bowl_mesh := CylinderMesh.new()
	bowl_mesh.top_radius = 0.5
	bowl_mesh.bottom_radius = 0.22
	bowl_mesh.height = 0.35
	bowl_mesh.material = stone
	bowl.mesh = bowl_mesh
	bowl.position = Vector3(0, 1.15, 0)
	add_child(bowl)

	# Cold coals; they start glowing when lit.
	var coal := StandardMaterial3D.new()
	coal.albedo_color = Color(0.12, 0.1, 0.09)
	coal.roughness = 1.0
	_coals = MeshInstance3D.new()
	var coals_mesh := SphereMesh.new()
	coals_mesh.radius = 0.34
	coals_mesh.height = 0.24
	coals_mesh.material = coal
	_coals.mesh = coals_mesh
	_coals.position = Vector3(0, 1.32, 0)
	add_child(_coals)


func _process(delta: float) -> void:
	if not is_lit:
		return
	_time += delta
	var flick := 1.0 + 0.10 * sin(_time * 9.7 + _phase) \
			+ 0.06 * sin(_time * 23.3 + _phase * 1.7)
	_light.light_energy = 2.6 * flick
	_core.scale = Vector3(
			1.0 + 0.08 * sin(_time * 15.9 + _phase * 2.0),
			1.0 + 0.18 * sin(_time * 11.3 + _phase),
			1.0 + 0.08 * cos(_time * 14.1 + _phase))


func can_interact() -> bool:
	return not is_lit


func interact() -> void:
	light()


func light() -> void:
	if is_lit:
		return
	is_lit = true

	var coal := StandardMaterial3D.new()
	coal.albedo_color = Color(0.5, 0.15, 0.03)
	coal.emission_enabled = true
	coal.emission = Color(1.0, 0.35, 0.05)
	coal.emission_energy_multiplier = 1.6
	(_coals.mesh as SphereMesh).material = coal

	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(1.0, 0.75, 0.3)
	core_mat.emission_enabled = true
	core_mat.emission = Color(1.0, 0.58, 0.1)
	core_mat.emission_energy_multiplier = 2.2
	_core = MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.12
	core_mesh.height = 0.42
	core_mesh.material = core_mat
	_core.mesh = core_mesh
	_core.position = Vector3(0, 1.55, 0)
	add_child(_core)

	var quad := QuadMesh.new()
	quad.size = Vector2(0.24, 0.24)
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
	particles.amount = 20
	particles.lifetime = 0.8
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.14
	particles.direction = Vector3.UP
	particles.spread = 14.0
	particles.gravity = Vector3.ZERO
	particles.initial_velocity_min = 0.5
	particles.initial_velocity_max = 1.1
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.0
	particles.scale_amount_curve = fade
	particles.color_ramp = ramp
	particles.position = Vector3(0, 1.5, 0)
	add_child(particles)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.62, 0.28)
	_light.light_energy = 2.6
	_light.omni_range = 10.0
	_light.position = Vector3(0, 1.8, 0)
	add_child(_light)

	lit_changed.emit()
