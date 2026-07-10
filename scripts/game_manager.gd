extends Node

signal scarab_count_changed(current: int, required: int)
signal all_scarabs_collected
signal gate_opened
signal game_won

const REQUIRED_SCARABS: int = 3
const MAIN_MENU_SCENE: String = "res://ui/main_menu.tscn"
const TOMB_SCENE: String = "res://levels/tomb.tscn"
const WIN_SCREEN_SCENE: String = "res://ui/win_screen.tscn"

var collected_scarabs: int = 0
var gate_is_open: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func reset_run() -> void:
	collected_scarabs = 0
	gate_is_open = false
	get_tree().paused = false
	scarab_count_changed.emit(collected_scarabs, REQUIRED_SCARABS)


func start_game() -> void:
	reset_run()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().change_scene_to_file(TOMB_SCENE)


func show_main_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func collect_scarab() -> void:
	if collected_scarabs >= REQUIRED_SCARABS:
		return

	collected_scarabs += 1
	scarab_count_changed.emit(collected_scarabs, REQUIRED_SCARABS)

	if collected_scarabs >= REQUIRED_SCARABS:
		gate_is_open = true
		all_scarabs_collected.emit()
		gate_opened.emit()


func win_game() -> void:
	if not gate_is_open:
		return

	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game_won.emit()
	get_tree().call_deferred("change_scene_to_file", WIN_SCREEN_SCENE)


func quit_game() -> void:
	get_tree().quit()
