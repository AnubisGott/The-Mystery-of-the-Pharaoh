extends Node

signal game_won
signal god_mode_changed(enabled: bool)
signal music_enabled_changed(enabled: bool)
signal music_finished
signal display_changed
signal language_changed

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

# Supported locales in menu order, each with its own native name (shown
# untranslated on the language button). Must match the columns of
# localization/strings.csv.
const LANGUAGES: Array[Array] = [
	["en", "English"],
	["de", "Deutsch"],
	["fr", "Français"],
	["es", "Español"],
	["it", "Italiano"],
	["pt_BR", "Português (Brasil)"],
	["pl", "Polski"],
	["ru", "Русский"],
	["tr", "Türkçe"],
	["ja", "日本語"],
	["zh_CN", "简体中文"],
	["ko", "한국어"],
]

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
# Locale code from LANGUAGES; empty until resolved (saved setting, or the
# OS language on first launch).
var language: String = ""
# Separate loudness for effects and music (0..1), each on its own audio
# bus; the options sliders override the defaults.
var sound_volume: float = 0.5
var music_volume: float = 0.1

var _music_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_buses()
	_extend_font_fallbacks()
	_load_settings()
	_apply_language()
	_apply_display()
	_apply_volumes()
	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = -6.0
	_music_player.bus = "Music"
	add_child(_music_player)
	# Fires only for non-looping tracks (the credits use it to end the game).
	_music_player.finished.connect(func() -> void: music_finished.emit())
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


# Every sound effect plays on the "Sfx" bus and the music on "Music",
# so the two sliders do not affect each other.
func _create_buses() -> void:
	for bus_name in ["Sfx", "Music"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var index := AudioServer.bus_count
			AudioServer.add_bus(index)
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")


func set_sound_volume(value: float) -> void:
	sound_volume = clampf(value, 0.0, 1.0)
	_apply_volumes()
	_save_settings()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_volumes()
	_save_settings()


func _apply_volumes() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Sfx"),
			linear_to_db(maxf(sound_volume, 0.001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"),
			linear_to_db(maxf(music_volume, 0.001)))


# The built-in UI font has no CJK glyphs; chain the Windows system fonts
# behind it so Japanese, Chinese and Korean render without bundled fonts.
func _extend_font_fallbacks() -> void:
	ThemeDB.fallback_font.fallbacks = cjk_fallback_fonts()


# One SystemFont per script family (no single family covers all three
# scripts). Each lists the Windows font first and its Linux equivalent
# (Noto, preinstalled on most distros) second - SystemFont picks the
# first name available on the machine.
static func cjk_fallback_fonts(weight: int = 400) -> Array[Font]:
	var chain: Array[Font] = []
	for family: Array in [
		["Yu Gothic UI", "Noto Sans CJK JP"],
		["Microsoft YaHei UI", "Noto Sans CJK SC"],
		["Malgun Gothic", "Noto Sans CJK KR"],
	]:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(family)
		font.font_weight = weight
		chain.append(font)
	return chain


func set_language(code: String) -> void:
	if language == code:
		return
	language = code
	TranslationServer.set_locale(code)
	_save_settings()
	language_changed.emit()


func _apply_language() -> void:
	if language.is_empty():
		language = _default_language()
	TranslationServer.set_locale(language)


# The supported locale matching the OS language, or English.
func _default_language() -> String:
	var os_lang: String = OS.get_locale_language()
	match os_lang:
		"zh":
			return "zh_CN"
		"pt":
			return "pt_BR"
	for entry in LANGUAGES:
		if entry[0] == os_lang:
			return os_lang
	return "en"


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
		# Match the screen size while still windowed: a stale small size
		# carried into fullscreen shows a cut-off picture on some setups.
		window.size = DisplayServer.screen_get_size(window.current_screen)
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
	config.set_value("general", "language", language)
	config.set_value("audio", "sound_volume", sound_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "music", music_enabled)
	config.save(SETTINGS_PATH)


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	fullscreen = config.get_value("display", "fullscreen", fullscreen)
	window_size = config.get_value("display", "window_size", window_size)
	language = str(config.get_value("general", "language", language))
	sound_volume = config.get_value("audio", "sound_volume", sound_volume)
	music_volume = config.get_value("audio", "music_volume", music_volume)
	music_enabled = config.get_value("audio", "music", music_enabled)


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
	_save_settings()


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
