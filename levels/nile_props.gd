extends Object
class_name NileProps

# Procedural props for the Nile levels: the paddle steamboat (Level 6
# finish line, Level 7 stage) and the palm trees along the banks.


static func build_boat() -> Node3D:
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.92, 0.9, 0.85)
	white.roughness = 0.6
	var cream := StandardMaterial3D.new()
	cream.albedo_color = Color(0.85, 0.78, 0.62)
	cream.roughness = 0.7
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.15, 0.13, 0.12)
	dark.roughness = 0.5
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.6, 0.15, 0.1)
	red.roughness = 0.6
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.4, 0.28, 0.16)
	wood.roughness = 0.9

	var boat := Node3D.new()
	boat.name = "Boat"
	# Hull with a raked bow block, then two decks, cabins and the funnel.
	_box(boat, white, Vector3(4.5, 1.4, 11.0), Vector3(0, 0.2, 0))
	_box(boat, white, Vector3(3.2, 1.2, 1.8), Vector3(0, 0.25, -6.0))
	_box(boat, wood, Vector3(4.2, 0.25, 10.6), Vector3(0, 1.0, 0))
	_box(boat, cream, Vector3(3.4, 1.6, 7.0), Vector3(0, 1.9, 0.4))
	_box(boat, dark, Vector3(3.45, 0.5, 6.0), Vector3(0, 2.0, 0.4))
	_box(boat, wood, Vector3(3.8, 0.2, 7.6), Vector3(0, 2.8, 0.4))
	_box(boat, cream, Vector3(2.6, 1.3, 4.6), Vector3(0, 3.5, 0.6))
	_box(boat, dark, Vector3(2.65, 0.4, 3.8), Vector3(0, 3.6, 0.6))
	_box(boat, wood, Vector3(3.0, 0.15, 5.0), Vector3(0, 4.2, 0.6))

	var funnel := MeshInstance3D.new()
	var funnel_mesh := CylinderMesh.new()
	funnel_mesh.top_radius = 0.32
	funnel_mesh.bottom_radius = 0.4
	funnel_mesh.height = 2.2
	funnel_mesh.material = dark
	funnel.mesh = funnel_mesh
	funnel.position = Vector3(0, 5.2, -0.8)
	boat.add_child(funnel)
	var band := MeshInstance3D.new()
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = 0.42
	band_mesh.bottom_radius = 0.42
	band_mesh.height = 0.35
	band_mesh.material = red
	band.mesh = band_mesh
	band.position = Vector3(0, 5.6, -0.8)
	boat.add_child(band)

	# Side paddle wheels in their red housings.
	for side: float in [-1.0, 1.0]:
		_box(boat, red, Vector3(0.5, 2.0, 3.2), Vector3(side * 2.4, 1.1, 1.6))
		_box(boat, dark, Vector3(0.55, 0.3, 3.3), Vector3(side * 2.4, 2.15, 1.6))

	# Smoke from the funnel — part of the boat, so it steams identically
	# at the Level-6 jetty and on the Level-7 journey.
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	var smoke_material := StandardMaterial3D.new()
	smoke_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smoke_material.vertex_color_use_as_albedo = true
	quad.material = smoke_material
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 0.4))
	fade.add_point(Vector2(1.0, 1.0))
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.3, 0.3, 0.3, 0.6))
	ramp.set_color(1, Color(0.6, 0.6, 0.6, 0.0))
	var smoke := CPUParticles3D.new()
	smoke.mesh = quad
	smoke.amount = 24
	smoke.lifetime = 3.5
	smoke.direction = Vector3(0.3, 1, 0)
	smoke.spread = 10.0
	smoke.gravity = Vector3.ZERO
	smoke.initial_velocity_min = 0.8
	smoke.initial_velocity_max = 1.4
	smoke.scale_amount_min = 0.6
	smoke.scale_amount_max = 1.0
	smoke.scale_amount_curve = fade
	smoke.color_ramp = ramp
	smoke.position = Vector3(0, 6.4, -0.8)
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


static func _box(parent: Node3D, material: Material, size: Vector3, pos: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	mesh.mesh = box
	mesh.position = pos
	parent.add_child(mesh)
