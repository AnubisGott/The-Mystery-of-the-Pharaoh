extends Node

signal game_won
signal god_mode_changed(enabled: bool)
signal music_enabled_changed(enabled: bool)

const MAIN_MENU_SCENE: String = "res://ui/main_menu.tscn"
const PATH_SCENE: String = "res://levels/path.tscn"
const WIN_SCREEN_SCENE: String = "res://ui/win_screen.tscn"

# Hidden cheat, toggled with Alt+Shift+G: spears cannot kill.
var god_mode: bool = false
var music_enabled: bool = true

var _music_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = -6.0
	add_child(_music_player)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_music"):
		set_music_enabled(not music_enabled)
		return

	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_G and event.alt_pressed and event.shift_pressed:
		god_mode = not god_mode
		god_mode_changed.emit(god_mode)


# Starts the track from the beginning (if music is enabled). The player
# lives on the autoload, so music survives scene changes until the next
# scene requests its own track.
func play_music(stream: AudioStream) -> void:
	if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
		stream.loop = true
	_music_player.stream = stream
	if music_enabled:
		_music_player.play()


func set_music_enabled(enabled: bool) -> void:
	if music_enabled == enabled:
		return

	music_enabled = enabled
	music_enabled_changed.emit(enabled)
	if enabled and _music_player.stream != null:
		_music_player.play()
	elif not enabled:
		_music_player.stop()


func start_game() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().change_scene_to_file(PATH_SCENE)


func show_main_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func win_game() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game_won.emit()
	get_tree().call_deferred("change_scene_to_file", WIN_SCREEN_SCENE)


func quit_game() -> void:
	get_tree().quit()
