extends Object
class_name NileProps

# Props for the Nile levels: the paddle steamer (Level 6 finish line,
# Level 7 stage — a CC-BY model, see models/CREDITS.md) and the
# procedural palm trees along the banks.

const STEAMSHIP: PackedScene = preload("res://models/steamship.glb")


static func build_boat() -> Node3D:
	var boat := Node3D.new()
	boat.name = "Boat"
	boat.add_child(STEAMSHIP.instantiate())

	# Smoke from the two funnels — part of the boat, so it steams
	# identically at the Level-6 jetty and on the Level-7 journey.
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.55)
	var smoke_material := StandardMaterial3D.new()
	smoke_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smoke_material.vertex_color_use_as_albedo = true
	# A radial falloff so each particle is a soft puff — the bare quad
	# reads as a hard-edged square while young and still opaque.
	var soft := Gradient.new()
	soft.set_color(0, Color(1, 1, 1, 1))
	soft.set_color(1, Color(1, 1, 1, 0))
	var puff := GradientTexture2D.new()
	puff.gradient = soft
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(0.5, 0.0)
	smoke_material.albedo_texture = puff
	quad.material = smoke_material
	# Puffs start small and quick so they clear the cap instead of
	# pooling into a dark ball on it, then swell as they thin out.
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 0.6))
	fade.add_point(Vector2(1.0, 1.0))
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.5, 0.5, 0.5, 0.3))
	ramp.set_color(1, Color(0.62, 0.62, 0.62, 0.0))
	for funnel_x: float in [-0.8, 0.8]:
		var smoke := CPUParticles3D.new()
		smoke.mesh = quad
		smoke.amount = 10
		smoke.lifetime = 3.5
		smoke.direction = Vector3(0.3, 1, 0)
		smoke.spread = 10.0
		smoke.gravity = Vector3.ZERO
		smoke.initial_velocity_min = 1.6
		smoke.initial_velocity_max = 2.2
		smoke.scale_amount_min = 0.6
		smoke.scale_amount_max = 1.0
		smoke.scale_amount_curve = fade
		smoke.color_ramp = ramp
		smoke.position = Vector3(funnel_x, 4.85, -2.18)
		boat.add_child(smoke)
	return boat


static func build_palm(height: float = 5.0) -> Node3D:
	var trunk_material := StandardMaterial3D.new()
	trunk_material.albedo_color = Color(0.45, 0.33, 0.2)
	trunk_material.roughness = 1.0
	var leaf_material := StandardMaterial3D.new()
	leaf_material.albedo_color = Color(0.2, 0.45, 0.18)
	leaf_material.roughness = 0.9

	var palm := Node3D.new()
	# A gently leaning trunk out of stacked segments.
	var segments := 5
	for i in segments:
		var segment := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.14 - 0.012 * i
		cylinder.bottom_radius = 0.17 - 0.012 * i
		cylinder.height = height / segments + 0.08
		cylinder.material = trunk_material
		segment.mesh = cylinder
		var lean := 0.06 * i * i
		segment.position = Vector3(lean, (i + 0.5) * height / segments, 0)
		segment.rotation.z = -0.07 * i
		palm.add_child(segment)

	var crown_x := 0.06 * (segments - 1) * (segments - 1)
	for i in 7:
		var frond := MeshInstance3D.new()
		var leaf := BoxMesh.new()
		leaf.size = Vector3(0.25, 0.05, 2.6)
		leaf.material = leaf_material
		frond.mesh = leaf
		frond.position = Vector3(crown_x, height + 0.1, 0)
		frond.rotation.y = TAU * i / 7.0
		frond.rotation.x = -0.45
		# Push each frond outward along its own direction.
		frond.translate_object_local(Vector3(0, 0, -1.0))
		palm.add_child(frond)
	return palm
