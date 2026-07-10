extends Control

@onready var start_button: Button = $Center/Panel/MenuItems/StartButton
@onready var quit_button: Button = $Center/Panel/MenuItems/QuitButton
@onready var music_button: Button = $Center/Panel/MenuItems/MusicButton
@onready var music_player: AudioStreamPlayer = $MusicPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	music_button.pressed.connect(_on_music_pressed)
	start_button.grab_focus()

	music_player.stream.loop = true
	_apply_music_setting()


func _on_start_pressed() -> void:
	GameManager.start_game()


func _on_quit_pressed() -> void:
	GameManager.quit_game()


func _on_music_pressed() -> void:
	GameManager.music_enabled = not GameManager.music_enabled
	_apply_music_setting()


func _apply_music_setting() -> void:
	music_button.text = "Music: On" if GameManager.music_enabled else "Music: Off"
	if GameManager.music_enabled:
		if not music_player.playing:
			music_player.play()
	else:
		music_player.stop()
