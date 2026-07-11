extends Node

signal game_won
signal god_mode_changed(enabled: bool)
signal music_enabled_changed(enabled: bool)
signal display_changed

const MAIN_MENU_SCENE: String = "res://ui/main_menu.tscn"
const WIN_SCREEN_SCENE: String = "res://ui/win_screen.tscn"
const LEVEL_SCENES: Array[String] = [
	"res://levels/path.tscn",
	"res://levels/pendulum_hall.tscn",
	"res://levels/stairs.tscn",
	"res://levels/burial_chamber.tscn",
	"res://levels/slide.tscn",
	"res://levels/crocodiles.tscn",
	"res://levels/nile_credits.tscn",
]

const SETTINGS_PATH: String = "user://settings.cfg"

# Window size presets: common 16:9 steps (HD, Full HD, QHD, 4K) plus two
# 21:9 widescreen sizes. The menu only offers those fitting the screen.
const WINDOW_SIZES: Array[Vector2i] = [
	Vector2i(1152, 648),
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1080),
	Vector2i(2560, 1440),
	Vector2i(3440, 1440),
	Vector2i(3840, 2160),
]

var current_level: int = 0

# Hidden cheat, toggled with Alt+Shift+G: spears cannot kill.
var god_mode: bool = false
var music_enabled: bool = true

var fullscreen: bool = false
var window_size: Vector2i = Vector2i(1152, 648)

var _music_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	_apply_display()
	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = -6.0
	add_child(_music_player)
	# Route window-close through quit_game() so the music stops a frame
	# before shutdown: an MP3 still playing at exit leaks its playback
	# object (cosmetic engine warning).
	get_tree().auto_accept_quit = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_music"):
		set_music_enabled(not music_enabled)
		return

	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F11:
		set_fullscreen(not fullscreen)
		return

	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_G and event.alt_pressed and event.shift_pressed:
		god_mode = not god_mode
		god_mode_changed.emit(god_mode)


func set_fullscreen(enabled: bool) -> void:
	if fullscreen == enabled:
		return
	fullscreen = enabled
	_apply_display()
	_save_settings()
	display_changed.emit()


func set_window_size(size: Vector2i) -> void:
	if window_size == size:
		return
	window_size = size
	_apply_display()
	_save_settings()
	display_changed.emit()


# The presets from WINDOW_SIZES that fit the player's screen. Headless
# runs report a zero screen; offer everything there.
func available_window_sizes() -> Array[Vector2i]:
	var screen: Vector2i = DisplayServer.screen_get_size()
	var sizes: Array[Vector2i] = []
	for size in WINDOW_SIZES:
		if screen.x <= 0 or (size.x <= screen.x and size.y <= screen.y):
			sizes.append(size)
	if sizes.is_empty():
		sizes.append(WINDOW_SIZES[0])
	return sizes


func _apply_display() -> void:
	# Headless runs (tests) have no real window to change.
	if DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	if fullscreen:
		window.mode = Window.MODE_FULLSCREEN
	else:
		window.mode = Window.MODE_WINDOWED
		window.size = window_size
		# Center on the current screen so a size change never leaves the
		# title bar off the desktop.
		var usable: Rect2i = DisplayServer.screen_get_usable_rect(window.current_screen)
		window.position = usable.position + (usable.size - window_size) / 2


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("display", "window_size", window_size)
	config.save(SETTINGS_PATH)


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	fullscreen = config.get_value("display", "fullscreen", fullscreen)
	window_size = config.get_value("display", "window_size", window_size)


# Starts the track from the beginning (if music is enabled). The player
# lives on the autoload, so music survives scene changes until the next
# scene requests its own track.
func play_music(stream: AudioStream, loop: bool = true) -> void:
	if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
		stream.loop = loop
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
	start_level(0)


func start_level(index: int) -> void:
	current_level = clampi(index, 0, LEVEL_SCENES.size() - 1)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().change_scene_to_file(LEVEL_SCENES[current_level])


# Called by a level's exit zone: loads the next level, or the win
# screen after the last one.
func complete_level() -> void:
	current_level += 1
	if current_level < LEVEL_SCENES.size():
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_tree().call_deferred("change_scene_to_file", LEVEL_SCENES[current_level])
	else:
		win_game()


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
	# Any stream still playing at shutdown leaks its playback object;
	# stop every audio player in the tree, give the audio server one
	# frame to release them, then quit.
	for player in get_tree().root.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	for player in get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false):
		player.stop()
	_music_player.stop()
	_music_player.stream = null
	await get_tree().process_frame
	get_tree().quit()
