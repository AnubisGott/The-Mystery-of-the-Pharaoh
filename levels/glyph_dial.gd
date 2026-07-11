extends Node3D

# A stone dial in the burial chamber bearing a hieroglyph. Interacting
# rotates the drum a quarter turn; the level counts each dial that has
# been turned at least once. Faces +Z (rotate the node to aim it).

signal turned

var prompt: String = "Turn the dial"
var glyph_kind: int = 0
var was_turned: bool = false

var _drum: Node3D
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

	var glyph := Glyphs.build(glyph_kind, 0.42)
	glyph.position = Vector3(0, 0, 0.44)
	_drum.add_child(glyph)


func can_interact() -> bool:
	return not _spinning


func interact() -> void:
	if _spinning:
		return
	_spinning = true
	var tween := create_tween()
	tween.tween_property(_drum, "rotation:y", _drum.rotation.y + TAU / 4.0, 0.6) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(_on_spin_finished)


# The dial only counts once its quarter-turn has visibly completed —
# the finale must not fire while the wheel is still spinning.
func _on_spin_finished() -> void:
	_spinning = false
	if not was_turned:
		was_turned = true
		turned.emit()
