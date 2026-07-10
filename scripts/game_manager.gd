extends Node

signal game_won
signal god_mode_changed(enabled: bool)

const MAIN_MENU_SCENE: String = "res://ui/main_menu.tscn"
const PATH_SCENE: String = "res://levels/path.tscn"
const WIN_SCREEN_SCENE: String = "res://ui/win_screen.tscn"

# Hidden cheat, toggled with Ctrl+Shift+G: spears cannot kill.
var god_mode: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_G and event.ctrl_pressed and event.shift_pressed:
		god_mode = not god_mode
		god_mode_changed.emit(god_mode)


func start_game() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().change_scene_to_file(PATH_SCENE)


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
	get_tree().quit()
