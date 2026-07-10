extends Control

const MENU_MUSIC: AudioStream = preload("res://soundAndMusic/music/AztekenherausforderungLevel01.mp3")

@onready var start_button: Button = $Center/Panel/MenuItems/StartButton
@onready var quit_button: Button = $Center/Panel/MenuItems/QuitButton
@onready var music_button: Button = $Center/Panel/MenuItems/MusicButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	music_button.pressed.connect(_on_music_pressed)
	GameManager.music_enabled_changed.connect(_on_music_enabled_changed)
	start_button.grab_focus()

	GameManager.play_music(MENU_MUSIC)
	_update_music_label()


func _on_start_pressed() -> void:
	GameManager.start_game()


func _on_quit_pressed() -> void:
	GameManager.quit_game()


func _on_music_pressed() -> void:
	GameManager.set_music_enabled(not GameManager.music_enabled)


func _on_music_enabled_changed(_enabled: bool) -> void:
	_update_music_label()


func _update_music_label() -> void:
	music_button.text = "Music: On (M)" if GameManager.music_enabled else "Music: Off (M)"
