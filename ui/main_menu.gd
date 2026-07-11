extends Control

const MENU_MUSIC: AudioStream = preload("res://soundAndMusic/music/AztekenherausforderungLevel01.mp3")

@onready var level1_button: Button = $Center/Panel/MenuItems/Level1Button
@onready var level2_button: Button = $Center/Panel/MenuItems/Level2Button
@onready var level3_button: Button = $Center/Panel/MenuItems/Level3Button
@onready var quit_button: Button = $Center/Panel/MenuItems/QuitButton
@onready var music_button: Button = $Center/Panel/MenuItems/MusicButton
@onready var display_button: Button = $Center/Panel/MenuItems/DisplayButton
@onready var size_button: Button = $Center/Panel/MenuItems/SizeButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	level1_button.pressed.connect(_on_level_pressed.bind(0))
	level2_button.pressed.connect(_on_level_pressed.bind(1))
	level3_button.pressed.connect(_on_level_pressed.bind(2))
	quit_button.pressed.connect(_on_quit_pressed)
	music_button.pressed.connect(_on_music_pressed)
	display_button.pressed.connect(_on_display_pressed)
	size_button.pressed.connect(_on_size_pressed)
	GameManager.music_enabled_changed.connect(_on_music_enabled_changed)
	GameManager.display_changed.connect(_update_display_labels)
	level1_button.grab_focus()

	GameManager.play_music(MENU_MUSIC)
	_update_music_label()
	_update_display_labels()


func _on_level_pressed(index: int) -> void:
	GameManager.start_level(index)


func _on_quit_pressed() -> void:
	GameManager.quit_game()


func _on_music_pressed() -> void:
	GameManager.set_music_enabled(not GameManager.music_enabled)


func _on_music_enabled_changed(_enabled: bool) -> void:
	_update_music_label()


func _update_music_label() -> void:
	music_button.text = "Music: On (M)" if GameManager.music_enabled else "Music: Off (M)"


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
