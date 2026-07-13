extends VBoxContainer

# The shared options controls — display mode, window size, music
# on/off and the two loudness sliders (sound effects and music) — used
# by both the main menu and the in-game pause menu. Emits `closed`
# when Back is pressed; the host decides what to show instead.

signal closed

@onready var music_button: Button = $MusicButton
@onready var language_button: Button = $LanguageButton
@onready var display_button: Button = $DisplayButton
@onready var size_button: Button = $SizeButton
@onready var sound_slider: HSlider = $SoundSlider
@onready var music_slider: HSlider = $MusicSlider
@onready var back_button: Button = $BackButton


func _ready() -> void:
	music_button.pressed.connect(_on_music_pressed)
	language_button.pressed.connect(_on_language_pressed)
	display_button.pressed.connect(_on_display_pressed)
	size_button.pressed.connect(_on_size_pressed)
	back_button.pressed.connect(_on_back_pressed)
	sound_slider.value = GameManager.sound_volume * 100.0
	sound_slider.value_changed.connect(_on_sound_volume_changed)
	music_slider.value = GameManager.music_volume * 100.0
	music_slider.value_changed.connect(_on_music_volume_changed)
	GameManager.music_enabled_changed.connect(_on_music_enabled_changed)
	GameManager.display_changed.connect(_update_display_labels)
	GameManager.language_changed.connect(_on_language_changed)
	_update_music_label()
	_update_language_label()
	_update_display_labels()


func focus() -> void:
	back_button.grab_focus()


func _on_back_pressed() -> void:
	closed.emit()


func _on_music_pressed() -> void:
	GameManager.set_music_enabled(not GameManager.music_enabled)


func _on_music_enabled_changed(_enabled: bool) -> void:
	_update_music_label()


func _update_music_label() -> void:
	music_button.text = "Music: On (M)" if GameManager.music_enabled else "Music: Off (M)"


# Cycle through the supported languages.
func _on_language_pressed() -> void:
	var index := 0
	for i in GameManager.LANGUAGES.size():
		if GameManager.LANGUAGES[i][0] == GameManager.language:
			index = i
			break
	GameManager.set_language(GameManager.LANGUAGES[(index + 1) % GameManager.LANGUAGES.size()][0])


# Scene texts re-translate on their own; only the strings composed in
# code (language name, window size) need a refresh.
func _on_language_changed() -> void:
	_update_language_label()
	_update_display_labels()


func _update_language_label() -> void:
	for entry in GameManager.LANGUAGES:
		if entry[0] == GameManager.language:
			language_button.text = tr("Language: %s") % entry[1]
			return


func _on_sound_volume_changed(value: float) -> void:
	GameManager.set_sound_volume(value / 100.0)


func _on_music_volume_changed(value: float) -> void:
	GameManager.set_music_volume(value / 100.0)


func _on_display_pressed() -> void:
	GameManager.set_fullscreen(not GameManager.fullscreen)


# Cycle through the window sizes that fit this screen.
func _on_size_pressed() -> void:
	var sizes: Array[Vector2i] = GameManager.available_window_sizes()
	var index: int = sizes.find(GameManager.window_size)
	GameManager.set_window_size(sizes[(index + 1) % sizes.size()])


func _update_display_labels() -> void:
	if GameManager.fullscreen:
		display_button.text = "Display: Fullscreen (F11)"
		size_button.text = "Size: Desktop"
		size_button.disabled = true
	else:
		display_button.text = "Display: Windowed (F11)"
		size_button.text = tr("Size: %d x %d") % [GameManager.window_size.x, GameManager.window_size.y]
		size_button.disabled = false
