extends Control

const MENU_MUSIC: AudioStream = preload("res://soundAndMusic/music/AztekenherausforderungLevel01.mp3")

@onready var level_buttons: Array[Button] = [
	$Center/Panel/MenuItems/Level1Button,
	$Center/Panel/MenuItems/Level2Button,
	$Center/Panel/MenuItems/Level3Button,
	$Center/Panel/MenuItems/Level4Button,
	$Center/Panel/MenuItems/Level5Button,
	$Center/Panel/MenuItems/Level6Button,
	$Center/Panel/MenuItems/Level7Button,
]
@onready var menu_items: VBoxContainer = $Center/Panel/MenuItems
@onready var options_items: VBoxContainer = $Center/Panel/OptionsItems
@onready var options_button: Button = $Center/Panel/MenuItems/OptionsButton
@onready var quit_button: Button = $Center/Panel/MenuItems/QuitButton
@onready var version_label: Label = $VersionLabel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The version lives in project.godot (application/config/version).
	version_label.text = "v" + str(ProjectSettings.get_setting(
			"application/config/version", "?"))
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in level_buttons.size():
		level_buttons[i].pressed.connect(_on_level_pressed.bind(i))
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	options_items.closed.connect(_on_options_closed)
	level_buttons[0].grab_focus()

	if GameManager.touch_mode:
		GameManager.scale_menu_for_touch(menu_items)
		GameManager.scale_menu_for_touch(options_items)

	GameManager.play_music(MENU_MUSIC)


func _on_level_pressed(index: int) -> void:
	GameManager.start_level(index)


func _on_options_pressed() -> void:
	menu_items.visible = false
	options_items.visible = true
	options_items.focus()


func _on_options_closed() -> void:
	options_items.visible = false
	menu_items.visible = true
	options_button.grab_focus()


func _on_quit_pressed() -> void:
	GameManager.quit_game()
