extends Node3D

# A stone dial in the burial chamber bearing a hieroglyph. Each F/E
# turn rotates the drum a quarter turn; the dial is solved once it has
# completed TWO full turns — its glyph then glows to show it sits in
# the right position. The finale needs every dial solved.

signal solved

const TURNS_REQUIRED: int = 2

var prompt: String = "Turn the dial"
var glyph_kind: int = 0
var turns_done: int = 0
var is_solved: bool = false

var _drum: Node3D
var _glyph: Node3D
var _spinning: bool = false


func _ready() -> void:
	add_to_group("interactables")

	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.5, 0.42, 0.32)
	stone.roughness = 0.9

	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.3
	base_mesh.bottom_radius = 0.38
	base_mesh.height = 0.9
	base_mesh.material = stone
	base.mesh = base_mesh
	base.position = Vector3(0, 0.45, 0)
	add_child(base)

	_drum = Node3D.new()
	_drum.position = Vector3(0, 1.25, 0)
	add_child(_drum)

	var drum_mesh_instance := MeshInstance3D.new()
	var drum_mesh := CylinderMesh.new()
	drum_mesh.top_radius = 0.42
	drum_mesh.bottom_radius = 0.42
	drum_mesh.height = 0.55
	drum_mesh.material = stone
	drum_mesh_instance.mesh = drum_mesh
	_drum.add_child(drum_mesh_instance)

	_glyph = Glyphs.build(glyph_kind, 0.42)
	_glyph.position = Vector3(0, 0, 0.44)
	_drum.add_child(_glyph)


func can_interact() -> bool:
	return not _spinning and not is_solved


func interact() -> void:
	if _spinning or is_solved:
		return
	_spinning = true
	var tween := create_tween()
	tween.tween_property(_drum, "rotation:y", _drum.rotation.y + TAU / 4.0, 0.6) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(_on_spin_finished)


# A turn only counts once the quarter-turn has visibly completed — the
# finale must not fire while a wheel is still spinning.
func _on_spin_finished() -> void:
	_spinning = false
	turns_done += 1
	if not is_solved and turns_done >= TURNS_REQUIRED:
		is_solved = true
		_set_glyph_glow()
		solved.emit()


# The solved position announces itself: the glyph lights up.
func _set_glyph_glow() -> void:
	for child in _glyph.get_children():
		var mesh_instance := child as MeshInstance3D
		if mesh_instance != null and mesh_instance.mesh is PrimitiveMesh:
			var material := (mesh_instance.mesh as PrimitiveMesh).material as StandardMaterial3D
			if material != null:
				material.emission_energy_multiplier = 2.6
