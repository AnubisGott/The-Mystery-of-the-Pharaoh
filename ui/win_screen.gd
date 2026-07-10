extends Control

const WIN_JINGLE: AudioStream = preload("res://soundAndMusic/sounds/LevelEndSuccess.mp3")

@onready var play_again_button: Button = $Center/Panel/MenuItems/PlayAgainButton
@onready var quit_button: Button = $Center/Panel/MenuItems/QuitButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	play_again_button.pressed.connect(_on_play_again_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	play_again_button.grab_focus()

	GameManager.play_music(WIN_JINGLE, false)


func _on_play_again_pressed() -> void:
	GameManager.start_game()


func _on_quit_pressed() -> void:
	GameManager.quit_game()
