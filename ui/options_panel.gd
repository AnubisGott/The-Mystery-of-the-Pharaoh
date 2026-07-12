extends VBoxContainer

# The shared options controls — display mode, window size, music
# on/off and the two loudness sliders (sound effects and music) — used
# by both the main menu and the in-game pause menu. Emits `closed`
# when Back is pressed; the host decides what to show instead.

signal closed

@onready var music_button: Button = $MusicButton
@onready var display_button: Button = $DisplayButton
@onready var size_button: Button = $SizeButton
@onready var sound_slider: HSlider = $SoundSlider
@onready var music_slider: HSlider = $MusicSlider
@onready var back_button: Button = $BackButton


func _ready() -> void:
	music_button.pressed.connect(_on_music_pressed)
	display_button.pressed.connect(_on_display_pressed)
	size_button.pressed.connect(_on_size_pressed)
	back_button.pressed.connect(_on_back_pressed)
	sound_slider.value = GameManager.sound_volume * 100.0
	sound_slider.value_changed.connect(_on_sound_volume_changed)
	music_slider.value = GameManager.music_volume * 100.0
	music_slider.value_changed.connect(_on_music_volume_changed)
	GameManager.music_enabled_changed.connect(_on_music_enabled_changed)
	GameManager.display_changed.connect(_update_display_labels)
	_update_music_label()
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
		size_button.text = "Size: %d x %d" % [GameManager.window_size.x, GameManager.window_size.y]
		size_button.disabled = false
