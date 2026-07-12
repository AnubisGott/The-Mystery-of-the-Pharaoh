extends Node2D

const WHOOSH_STREAMS: Array[AudioStream] = [
	preload("res://sounds/spear_whoosh_1.wav"),
	preload("res://sounds/spear_whoosh_2.wav"),
]
# Start the whoosh this long before the spear reaches screen center so
# its peak (the sound peaks ~0.3 s in) lands as the spear passes the
# character — independent of spear speed and window size.
const WHOOSH_LEAD_TIME: float = 0.31

var is_high: bool = false
var direction: float = 1.0
var speed: float = 900.0

var _whoosh_played: bool = false
var _whoosh_player: AudioStreamPlayer


func _ready() -> void:
	_whoosh_player = AudioStreamPlayer.new()
	_whoosh_player.volume_db = -6.0
	_whoosh_player.bus = "Sfx"
	add_child(_whoosh_player)


func _physics_process(delta: float) -> void:
	position.x += direction * speed * delta

	# The layer scales the whole spear with the window height; keep the
	# cleanup distance in the same units. The whoosh triggers on time-
	# to-center, so it works at any speed.
	var s := absf(scale.y)
	var width := get_viewport_rect().size.x
	if not _whoosh_played and absf(position.x - width * 0.5) < speed * WHOOSH_LEAD_TIME:
		_whoosh_played = true
		_whoosh_player.stream = WHOOSH_STREAMS[randi() % WHOOSH_STREAMS.size()]
		_whoosh_player.pitch_scale = randf_range(0.9, 1.15)
		_whoosh_player.play()

	if position.x < -150.0 * s or position.x > width + 150.0 * s:
		queue_free()


func _draw() -> void:
	# Drawn pointing right; flying left is mirrored via scale.x.
	draw_line(Vector2(-80.0, 0.0), Vector2(55.0, 0.0), Color(0.45, 0.3, 0.16), 7.0)
	var tip := PackedVector2Array([Vector2(55.0, -9.0), Vector2(92.0, 0.0), Vector2(55.0, 9.0)])
	draw_colored_polygon(tip, Color(0.75, 0.75, 0.78))
