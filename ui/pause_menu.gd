extends CanvasLayer

# In-level pause menu, opened with ESC: Resume, Reset Level, Main Menu
# and Quit Game. Lives in each level scene; it keeps processing while
# the tree is paused so it can unpause again.

@onready var resume_button: Button = $Root/Center/Panel/Items/ResumeButton
@onready var options_button: Button = $Root/Center/Panel/Items/OptionsButton
@onready var reset_button: Button = $Root/Center/Panel/Items/ResetButton
@onready var menu_button: Button = $Root/Center/Panel/Items/MenuButton
@onready var quit_button: Button = $Root/Center/Panel/Items/QuitButton
@onready var items: VBoxContainer = $Root/Center/Panel/Items
@onready var options_items: VBoxContainer = $Root/Center/Panel/OptionsItems


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	resume_button.pressed.connect(close)
	options_button.pressed.connect(_on_options_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	menu_button.pressed.connect(_on_menu_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	options_items.closed.connect(_on_options_closed)

	if GameManager.touch_mode:
		GameManager.scale_menu_for_touch(items)
		GameManager.scale_menu_for_touch(options_items)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	options_items.visible = false
	items.visible = true
	resume_button.grab_focus()


func _on_options_pressed() -> void:
	items.visible = false
	options_items.visible = true
	options_items.focus()


func _on_options_closed() -> void:
	options_items.visible = false
	items.visible = true
	options_button.grab_focus()


func close() -> void:
	visible = false
	get_tree().paused = false
	# Phones have no mouse to capture (and doing so hides the touch UI).
	if not GameManager.touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_reset_pressed() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().reload_current_scene()


func _on_menu_pressed() -> void:
	get_tree().paused = false
	GameManager.show_main_menu()


func _on_quit_pressed() -> void:
	GameManager.quit_game()
