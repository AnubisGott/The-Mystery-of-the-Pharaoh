extends Node3D

# A stone dial in the burial chamber bearing FOUR hieroglyphs, one per
# drum quarter — every F/E press grinds the next symbol to the front,
# endlessly, like a combination lock. The dial is solved while its
# TARGET glyph (matching the wall glyph above) faces the room; it
# starts two turns away, and there is no glow hint — the wall glyph is
# the only clue. The finale needs every dial solved at the same time.

signal solved

const TURN_SOUND: AudioStream = preload("res://sounds/stone_turn.wav")

# How many quarter turns from the start until the target faces front.
const TURNS_TO_TARGET: int = 2
const GLYPH_KINDS: int = 4

var prompt: String = "Turn the dial"
var glyph_kind: int = 0
var turns_done: int = 0
var is_solved: bool = false

var _drum: Node3D
var _spinning: bool = false
var _turn_player: AudioStreamPlayer3D


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

	# Four symbols around the drum. The target keeps the ORIGINAL
	# single-glyph mount at local +Z (slot 0): the dial's room rotation
	# points that slot at the wall, and after TURNS_TO_TARGET quarter
	# turns it comes around to face the room. The other three slots
	# carry the remaining glyph kinds.
	var others: Array[int] = []
	for kind in GLYPH_KINDS:
		if kind != glyph_kind:
			others.append(kind)
	for slot in 4:
		var kind: int = glyph_kind if slot == 0 else others.pop_front()
		var glyph := Glyphs.build(kind, 0.42)
		var angle := TAU / 4.0 * slot
		glyph.position = Vector3(sin(angle) * 0.44, 0, cos(angle) * 0.44)
		glyph.rotation.y = angle
		_drum.add_child(glyph)

	_turn_player = AudioStreamPlayer3D.new()
	_turn_player.stream = TURN_SOUND
	_turn_player.bus = "Sfx"
	_turn_player.volume_db = -10.0
	_turn_player.max_distance = 16.0
	_turn_player.position = Vector3(0, 1.25, 0)
	add_child(_turn_player)


func can_interact() -> bool:
	return not _spinning


func interact() -> void:
	if _spinning:
		return
	_spinning = true
	_turn_player.play()
	var tween := create_tween()
	tween.tween_property(_drum, "rotation:y", _drum.rotation.y + TAU / 4.0, 0.6) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(_on_spin_finished)


# A turn only counts once the quarter-turn has visibly completed — the
# finale must not fire while a wheel is still spinning. Turning past
# the target unsolves the dial again (the floor, once open, stays open).
func _on_spin_finished() -> void:
	_spinning = false
	turns_done += 1
	var was_solved := is_solved
	is_solved = (turns_done % 4) == TURNS_TO_TARGET
	if is_solved and not was_solved:
		solved.emit()
