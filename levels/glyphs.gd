extends Object
class_name Glyphs

# Stylized Egyptian hieroglyphs built from primitives, used on the
# burial-chamber dials and repeated on its walls: 0 = ankh,
# 1 = djed pillar, 2 = shen ring, 3 = pyramid. Built in the XY plane
# facing +Z; `size` is the glyph height.


static func build(kind: int, size: float, emissive: bool = true) -> Node3D:
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.85, 0.68, 0.25)
	gold.metallic = 0.6
	gold.roughness = 0.35
	if emissive:
		gold.emission_enabled = true
		gold.emission = Color(0.85, 0.6, 0.15)
		gold.emission_energy_multiplier = 0.7

	var root := Node3D.new()
	var s := size
	match kind:
		0:  # Ankh: loop on top of a cross.
			_bar(root, gold, Vector3(0.1 * s, 0.55 * s, 0.08 * s), Vector3(0, -0.2 * s, 0))
			_bar(root, gold, Vector3(0.5 * s, 0.1 * s, 0.08 * s), Vector3(0, 0.06 * s, 0))
			_ring(root, gold, 0.16 * s, 0.05 * s, Vector3(0, 0.3 * s, 0))
		1:  # Djed pillar: trunk with four crossbars.
			_bar(root, gold, Vector3(0.14 * s, 0.9 * s, 0.08 * s), Vector3(0, -0.05 * s, 0))
			for i in 4:
				_bar(root, gold, Vector3(0.5 * s, 0.07 * s, 0.09 * s),
						Vector3(0, (0.4 - i * 0.16) * s, 0))
		2:  # Shen ring: circle resting on a bar.
			_ring(root, gold, 0.27 * s, 0.07 * s, Vector3(0, 0.1 * s, 0))
			_bar(root, gold, Vector3(0.62 * s, 0.1 * s, 0.08 * s), Vector3(0, -0.4 * s, 0))
		_:  # Pyramid: two slanted flanks over a base line.
			_bar(root, gold, Vector3(0.1 * s, 0.62 * s, 0.08 * s),
					Vector3(-0.14 * s, 0.02 * s, 0), 0.5)
			_bar(root, gold, Vector3(0.1 * s, 0.62 * s, 0.08 * s),
					Vector3(0.14 * s, 0.02 * s, 0), -0.5)
			_bar(root, gold, Vector3(0.6 * s, 0.1 * s, 0.08 * s), Vector3(0, -0.28 * s, 0))
	return root


static func _bar(root: Node3D, material: Material, size: Vector3, pos: Vector3,
		rot_z: float = 0.0) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	mesh.mesh = box
	mesh.position = pos
	mesh.rotation.z = rot_z
	root.add_child(mesh)


static func _ring(root: Node3D, material: Material, radius: float, thickness: float,
		pos: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - thickness
	torus.outer_radius = radius + thickness
	torus.material = material
	mesh.mesh = torus
	mesh.position = pos
	mesh.rotation.x = PI / 2.0   # stand the ring upright in the XY plane
	root.add_child(mesh)
