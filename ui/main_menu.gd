extends Control

# The start menu, two levels deep: Select Level, Options and Quit up
# front; the seven levels (and Options' own panel) one step in. Esc - on
# Android the Back gesture - steps back out again.

const MENU_MUSIC: AudioStream = preload("res://soundAndMusic/music/AztekenherausforderungLevel01.mp3")

@onready var level_buttons: Array[Button] = [
	$Center/Panel/LevelItems/Level1Button,
	$Center/Panel/LevelItems/Level2Button,
	$Center/Panel/LevelItems/Level3Button,
	$Center/Panel/LevelItems/Level4Button,
	$Center/Panel/LevelItems/Level5Button,
	$Center/Panel/LevelItems/Level6Button,
	$Center/Panel/LevelItems/Level7Button,
]
@onready var menu_items: VBoxContainer = $Center/Panel/MenuItems
@onready var level_items: VBoxContainer = $Center/Panel/LevelItems
@onready var options_items: VBoxContainer = $Center/Panel/OptionsItems
@onready var select_level_button: Button = $Center/Panel/MenuItems/SelectLevelButton
@onready var options_button: Button = $Center/Panel/MenuItems/OptionsButton
@onready var quit_button: Button = $Center/Panel/MenuItems/QuitButton
@onready var level_back_button: Button = $Center/Panel/LevelItems/LevelBackButton
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
	select_level_button.pressed.connect(_on_select_level_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	level_back_button.pressed.connect(_show_top_level)
	options_items.closed.connect(_on_options_closed)
	select_level_button.grab_focus()

	if GameManager.touch_mode:
		# Only three entries up front: they get to be twice as big.
		GameManager.scale_menu_for_touch(menu_items, 2.0)
		GameManager.scale_menu_for_touch(level_items)
		GameManager.scale_menu_for_touch(options_items)

	GameManager.play_music(MENU_MUSIC)


# Esc (Android: Back) leaves a submenu; on the top level it does nothing,
# so the game is never closed by accident.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if level_items.visible:
		_show_top_level()
		get_viewport().set_input_as_handled()
	elif options_items.visible:
		_on_options_closed()
		get_viewport().set_input_as_handled()


func _show_top_level() -> void:
	level_items.visible = false
	options_items.visible = false
	menu_items.visible = true
	select_level_button.grab_focus()


func _on_select_level_pressed() -> void:
	menu_items.visible = false
	level_items.visible = true
	level_buttons[0].grab_focus()


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
