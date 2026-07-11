extends Node2D

const WHOOSH_STREAMS: Array[AudioStream] = [
	preload("res://sounds/spear_whoosh_1.wav"),
	preload("res://sounds/spear_whoosh_2.wav"),
]
# Start the whoosh this far before screen center so its peak lands
# as the spear passes the character (sound peaks at ~0.3 s, 900 px/s).
const WHOOSH_TRIGGER_DISTANCE: float = 280.0

var is_high: bool = false
var direction: float = 1.0
var speed: float = 900.0

var _whoosh_played: bool = false
var _whoosh_player: AudioStreamPlayer


func _ready() -> void:
	_whoosh_player = AudioStreamPlayer.new()
	_whoosh_player.volume_db = -6.0
	add_child(_whoosh_player)


func _physics_process(delta: float) -> void:
	position.x += direction * speed * delta

	# The layer scales the whole spear (and its speed) with the window
	# height; keep the trigger and cleanup distances in the same units.
	var s := absf(scale.y)
	var width := get_viewport_rect().size.x
	if not _whoosh_played and absf(position.x - width * 0.5) < WHOOSH_TRIGGER_DISTANCE * s:
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
