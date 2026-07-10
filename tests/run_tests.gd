extends Node

# Headless test suite. Run with:
#   godot --headless --path . res://tests/run_tests.tscn
# (or run-tests.bat). Exit code = number of failures.
#
# Every method named test_* runs in declaration order against one shared
# level instance; _reset_state() restores a clean world between tests.
const Spear2D := preload("res://hazards/spear_2d.gd")

const SPAWN_Z: float = 29.0

@onready var level: Node3D = $Level
@onready var player: CharacterBody3D = $Level/Player
@onready var layer: CanvasLayer = $Level/SpearLayer

var _failures := 0
var _test_failures := 0
var _current_test := ""


func _ready() -> void:
	# Deterministic world: no timer-driven spears during tests.
	level._spear_timer.stop()
	level._practice_timer.stop()

	var tests: Array[String] = []
	for m in get_method_list():
		if m.name.begins_with("test_") and not tests.has(m.name):
			tests.append(m.name)

	for test_name in tests:
		_current_test = test_name
		_test_failures = 0
		await _reset_state()
		await call(test_name)
		print("%s %s" % ["PASS" if _test_failures == 0 else "FAIL", test_name])

	print("%d tests, %d failures" % [tests.size(), _failures])
	get_tree().quit(_failures)


# ---------------------------------------------------------------- helpers

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		_test_failures += 1
		print("  FAIL [%s]: %s" % [_current_test, message])


func _reset_state() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "jump", "duck"]:
		Input.action_release(action)
	GameManager.god_mode = false
	layer._clear_spears()
	level._practice_high = false
	# Queued-free spears stay alive until frame end and can still score a
	# hit; let that frame pass, then wait out any running death sequence.
	await get_tree().physics_frame
	for i in 150:
		if not player.is_dying():
			break
		await get_tree().physics_frame
	player.reset_to_start(level._spawn_transform)
	await _settle()


# Waits for the death sequence to finish and the player to be reset.
func _await_death_reset() -> bool:
	for i in 150:
		await get_tree().physics_frame
		if player.global_position.z > 25.0 and not player.is_dying():
			return true
	return false


func _settle() -> void:
	for i in 60:
		await get_tree().physics_frame
		if player.is_on_floor():
			return


func _place_on_path(z: float) -> void:
	player.global_position = Vector3(level._path_x(z), 1.0, z)
	await _settle()


func _center_x() -> float:
	return get_viewport().get_visible_rect().size.x * 0.5


func _last_spear() -> Node2D:
	var spears := layer.get_children().filter(func(c): return c is Spear2D)
	return spears.back() if not spears.is_empty() else null


func _spear_count() -> int:
	return layer.get_children().filter(func(c): return c is Spear2D).size()


# Spawns a spear and places its tip at the given offset from screen center.
func _spawn_spear_with_tip_at(is_high: bool, tip_offset: float) -> Node2D:
	layer.spawn_spear(is_high, true)
	var spear := _last_spear()
	spear.position.x = _center_x() + tip_offset - 92.0
	return spear


# ------------------------------------------------------------- duck tests

func test_duck_shrinks_capsule() -> void:
	var capsule: CapsuleShape3D = player.get_node("CollisionShape3D").shape
	Input.action_press("duck")
	for i in 3:
		await get_tree().physics_frame
	_check(is_equal_approx(capsule.height, 1.3), "capsule not shrunk: %f" % capsule.height)

	Input.action_release("duck")
	for i in 3:
		await get_tree().physics_frame
	_check(is_equal_approx(capsule.height, 1.8), "capsule not restored: %f" % capsule.height)


func test_duck_keeps_feet_planted() -> void:
	var standing_feet: float = player.get_node("Visual").global_position.y

	Input.action_press("duck")
	await get_tree().physics_frame
	var ducked_feet: float = player.get_node("Visual").global_position.y
	for i in 5:
		await get_tree().physics_frame
	var settled_feet: float = player.get_node("Visual").global_position.y
	Input.action_release("duck")
	for i in 5:
		await get_tree().physics_frame
	var restored_feet: float = player.get_node("Visual").global_position.y

	_check(absf(ducked_feet - standing_feet) < 0.08, "feet moved on duck: %f" % ducked_feet)
	_check(absf(settled_feet - standing_feet) < 0.08, "feet drifted while ducked: %f" % settled_feet)
	_check(absf(restored_feet - standing_feet) < 0.08, "feet moved on stand up: %f" % restored_feet)


func test_duck_slows_movement() -> void:
	Input.action_press("duck")
	Input.action_press("move_forward")
	for i in 10:
		await get_tree().physics_frame
	var ducked_speed := Vector2(player.velocity.x, player.velocity.z).length()
	Input.action_release("duck")
	Input.action_release("move_forward")
	_check(ducked_speed < 3.0, "duck walk too fast: %f" % ducked_speed)


# ------------------------------------------------------------- jump tests

func test_jump_lifts_and_lands() -> void:
	var base_y := player.global_position.y
	Input.action_press("jump")
	var jumped := false
	var peak := 0.0
	for i in 120:
		await get_tree().physics_frame
		peak = maxf(peak, player.global_position.y - base_y)
		if not player.is_on_floor():
			jumped = true
		elif jumped:
			break
	Input.action_release("jump")

	_check(jumped, "jump never left the floor")
	_check(player.is_on_floor(), "player never landed")
	_check(peak > 0.4 and peak < 1.1, "jump peak out of range: %f" % peak)


func test_no_jump_while_ducking() -> void:
	Input.action_press("duck")
	for i in 3:
		await get_tree().physics_frame
	Input.action_press("jump")
	var left_floor := false
	for i in 20:
		await get_tree().physics_frame
		if not player.is_on_floor():
			left_floor = true
	Input.action_release("jump")
	Input.action_release("duck")
	_check(not left_floor, "player jumped while ducking")


func test_camera_steady_during_jump_and_duck() -> void:
	var pivot: Node3D = player.get_node("CameraPivot")
	var base_y: float = pivot.global_position.y

	Input.action_press("jump")
	var drift := 0.0
	for i in 70:
		await get_tree().physics_frame
		drift = maxf(drift, absf(pivot.global_position.y - base_y))
	Input.action_release("jump")
	_check(drift < 0.01, "camera moved %f during jump" % drift)

	Input.action_press("duck")
	drift = 0.0
	for i in 20:
		await get_tree().physics_frame
		drift = maxf(drift, absf(pivot.global_position.y - base_y))
	Input.action_release("duck")
	_check(drift < 0.01, "camera moved %f during duck" % drift)


# ------------------------------------------------------------- path tests

func test_path_straight_at_ends_winding_in_middle() -> void:
	for z in [50.0, 40.0, 21.0, -82.0, -95.0]:
		_check(absf(level._path_x(z)) < 0.001, "path not straight at z=%s" % z)

	for probe_z in [0.0, -40.0, -70.0]:
		var max_x := 0.0
		var z: float = probe_z + 4.0
		while z > probe_z - 4.0:
			max_x = maxf(max_x, absf(level._path_x(z)))
			z -= 0.5
		_check(max_x > 2.0, "winding weak around z=%s (max %f)" % [probe_z, max_x])


func test_clamp_keeps_player_on_path() -> void:
	await _place_on_path(10.0)
	var before := player.global_position
	for i in 3:
		await get_tree().physics_frame
	_check(player.global_position.distance_to(before) < 0.1, "on-path player was moved")

	for probe in [Vector3(10.0, 1.0, 5.0), Vector3(-12.0, 1.0, -8.0), Vector3(0.0, 1.0, 60.0)]:
		player.global_position = probe
		for i in 3:
			await get_tree().physics_frame
		var p := player.global_position
		var closest: Vector3 = level.get_node("Track").curve.get_closest_point(Vector3(p.x, 0.0, p.z))
		var dist := Vector2(p.x - closest.x, p.z - closest.z).length()
		_check(dist < 1.51, "player %s still %f m off the path" % [probe, dist])


func test_start_wall_blocks_backward() -> void:
	Input.action_press("move_back")
	for i in 120:
		await get_tree().physics_frame
	Input.action_release("move_back")
	var z := player.global_position.z
	_check(z > SPAWN_Z - 0.1 and z < 29.7, "expected block near wall, player at z=%f" % z)


func test_win_zone_on_path_and_reachable() -> void:
	var zone: Area3D = level.get_node("WinZone")
	var pos := zone.global_position
	var closest: Vector3 = level.get_node("Track").curve.get_closest_point(Vector3(pos.x, 0.0, pos.z))
	var dist := Vector2(pos.x - closest.x, pos.z - closest.z).length()
	_check(dist < 1.5, "win zone %f m off the reachable path corridor" % dist)


# ------------------------------------------------------------ spear tests

func test_low_spear_hits_standing_player() -> void:
	await _place_on_path(10.0)
	_spawn_spear_with_tip_at(false, -30.0)
	for i in 3:
		await get_tree().physics_frame
	_check(_spear_count() == 0, "spears not cleared after hit")
	_check(await _await_death_reset(), "standing player not reset by low spear")


func test_high_spear_hits_standing_player() -> void:
	await _place_on_path(10.0)
	_spawn_spear_with_tip_at(true, -30.0)
	for i in 3:
		await get_tree().physics_frame
	_check(await _await_death_reset(), "standing player not reset by high spear")


func test_head_hit_falls_forward() -> void:
	await _place_on_path(10.0)
	level._on_player_hit(true)
	for i in 10:
		await get_tree().physics_frame

	_check(player.is_dying(), "player not in dying state after hit")
	_check(player.get_node("HitPlayer") != null, "HitPlayer node missing")
	var visual: Node3D = player.get_node("Visual")
	_check(visual.rotation.x < -0.05, "head hit did not tip the body forward")

	_check(await _await_death_reset(), "death sequence did not end in a reset")
	_check(absf(visual.rotation.x) < 0.01, "body rotation not restored after reset")


func test_feet_hit_falls_backwards() -> void:
	await _place_on_path(10.0)
	level._on_player_hit(false)
	for i in 10:
		await get_tree().physics_frame

	_check(player.is_dying(), "player not in dying state after hit")
	var visual: Node3D = player.get_node("Visual")
	_check(visual.rotation.x > 0.05, "feet hit did not tip the body backwards")

	_check(await _await_death_reset(), "death sequence did not end in a reset")
	_check(absf(visual.rotation.x) < 0.01, "body rotation not restored after reset")


func test_ducking_dodges_high_spear() -> void:
	await _place_on_path(10.0)
	Input.action_press("duck")
	for i in 3:
		await get_tree().physics_frame
	_spawn_spear_with_tip_at(true, -30.0)
	for i in 3:
		await get_tree().physics_frame
	_check(player.global_position.z < 15.0, "ducking player was reset by high spear")

	# Keep ducking until the spear is gone: releasing mid-overlap would
	# legitimately count as a hit.
	layer._clear_spears()
	await get_tree().physics_frame
	Input.action_release("duck")


func test_jumping_dodges_low_spear() -> void:
	await _place_on_path(10.0)
	Input.action_release("jump")
	await get_tree().physics_frame
	Input.action_press("jump")
	for i in 15:
		await get_tree().physics_frame
		if not player.is_on_floor():
			break
	Input.action_release("jump")
	_check(not player.is_on_floor(), "could not get airborne")

	_spawn_spear_with_tip_at(false, -30.0)
	for i in 3:
		await get_tree().physics_frame
	_check(player.global_position.z < 15.0, "airborne player was reset by low spear")


func test_distant_spear_does_not_hit() -> void:
	await _place_on_path(10.0)
	_spawn_spear_with_tip_at(false, -200.0)
	await get_tree().physics_frame
	_check(player.global_position.z < 15.0, "distant spear counted as hit")


func test_only_one_spear_at_a_time() -> void:
	await _place_on_path(10.0)
	layer.spawn_spear(false, true)
	level._on_practice_timer_timeout()
	level._on_spear_timer_timeout()
	_check(_spear_count() == 1, "expected 1 spear in flight, found %d" % _spear_count())


func test_practice_spears_alternate_low_high() -> void:
	level._on_practice_timer_timeout()
	var first := _last_spear()
	var first_high: bool = first.is_high
	layer._clear_spears()
	await get_tree().physics_frame
	level._on_practice_timer_timeout()
	var second := _last_spear()
	_check(not first_high, "first practice spear should be low")
	_check(second.is_high, "second practice spear should be high")


func test_random_spears_wait_for_practice_zone() -> void:
	level._on_spear_timer_timeout()
	_check(_spear_count() == 0, "random spear spawned at start (z=%f)" % player.global_position.z)

	await _place_on_path(10.0)
	level._on_spear_timer_timeout()
	_check(_spear_count() == 1, "no random spear past the practice zone")


func test_spear_lanes_track_character() -> void:
	layer.spawn_spear(false, true)
	var low := _last_spear()
	layer.spawn_spear(true, true)
	var high := _last_spear()
	var view_height := get_viewport().get_visible_rect().size.y
	_check(low.position.y > high.position.y, "low lane not below high lane on screen")
	_check(low.position.y > 0.0 and low.position.y < view_height, "low lane off screen")
	_check(high.position.y > 0.0 and high.position.y < view_height, "high lane off screen")


# --------------------------------------------------------- god mode tests

func test_god_mode_shortcut_toggles() -> void:
	_press_god_key(false, true)
	await _await_input_dispatch()
	_check(GameManager.god_mode, "Alt+Shift+G did not enable god mode")

	_press_god_key(false, true)
	await _await_input_dispatch()
	_check(not GameManager.god_mode, "Alt+Shift+G did not disable god mode")

	_press_god_key(true, false)
	await _await_input_dispatch()
	_check(not GameManager.god_mode, "Ctrl+Shift+G must not toggle god mode")


func test_god_mode_prevents_reset() -> void:
	await _place_on_path(10.0)
	GameManager.god_mode = true
	level._on_player_hit(true)
	await get_tree().physics_frame
	_check(player.global_position.z < 15.0, "player was reset despite god mode")

	GameManager.god_mode = false
	level._on_player_hit(true)
	_check(await _await_death_reset(), "player not reset after god mode off")


func _press_god_key(with_ctrl: bool, with_alt: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_G
	ev.ctrl_pressed = with_ctrl
	ev.alt_pressed = with_alt
	ev.shift_pressed = true
	ev.pressed = true
	Input.parse_input_event(ev)


func _press_key(keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)


# Key events are dispatched on process frames, not physics frames.
func _await_input_dispatch() -> void:
	for i in 3:
		await get_tree().process_frame


# ------------------------------------------------------------ sound tests

func test_spear_whoosh_triggers_near_center() -> void:
	layer.spawn_spear(false, true)
	var spear := _last_spear()
	spear.position.x = _center_x() - Spear2D.WHOOSH_TRIGGER_DISTANCE - 120.0
	spear._physics_process(1.0 / 60.0)
	_check(not spear._whoosh_played, "whoosh played too far from center")

	spear.position.x = _center_x() - Spear2D.WHOOSH_TRIGGER_DISTANCE + 60.0
	spear._physics_process(1.0 / 60.0)
	_check(spear._whoosh_played, "whoosh not triggered near screen center")


func test_footsteps_fire_while_walking() -> void:
	_check(player.has_node("FootstepPlayer"), "FootstepPlayer node missing")

	Input.action_press("move_forward")
	var stepped := false
	for i in 90:
		await get_tree().physics_frame
		if player._last_step_index > 0:
			stepped = true
			break
	Input.action_release("move_forward")
	_check(stepped, "no footstep triggered while walking")

	for i in 10:
		await get_tree().physics_frame
	_check(player._last_step_index == 0, "step counter not reset when standing")


func test_menu_music_plays_and_toggles() -> void:
	GameManager.set_music_enabled(true)
	var menu: Control = load("res://ui/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().physics_frame

	var music: AudioStreamPlayer = GameManager._music_player
	var toggle: Button = menu.get_node("Center/Panel/MenuItems/MusicButton")
	_check(music.playing, "menu music not playing on start")
	_check(music.stream.loop, "menu music does not loop")
	_check(toggle.text == "Music: On (M)", "toggle label wrong while on")

	toggle.pressed.emit()
	_check(not GameManager.music_enabled, "toggle did not disable music setting")
	_check(not music.playing, "music still playing after toggle off")
	_check(toggle.text == "Music: Off (M)", "toggle label wrong while off")

	toggle.pressed.emit()
	_check(music.playing, "music not playing after toggle back on")

	menu.queue_free()
	await get_tree().physics_frame


func test_level_starts_music_and_m_key_toggles() -> void:
	GameManager.set_music_enabled(true)
	GameManager._music_player.stop()
	GameManager.play_music(level.LEVEL_MUSIC)
	_check(GameManager._music_player.playing, "level music not playing")
	_check(GameManager._music_player.stream == level.LEVEL_MUSIC, "level music wrong track")

	_press_key(KEY_M)
	await _await_input_dispatch()
	_check(not GameManager.music_enabled, "M key did not disable music")
	_check(not GameManager._music_player.playing, "music still playing after M")

	_press_key(KEY_M)
	await _await_input_dispatch()
	_check(GameManager.music_enabled, "M key did not re-enable music")
	_check(GameManager._music_player.playing, "music not resumed after M")


func test_win_screen_plays_success_jingle() -> void:
	GameManager.set_music_enabled(true)
	var win_screen: Control = load("res://ui/win_screen.tscn").instantiate()
	add_child(win_screen)
	await get_tree().physics_frame

	var music: AudioStreamPlayer = GameManager._music_player
	_check(music.playing, "win jingle not playing")
	_check(music.stream == win_screen.WIN_JINGLE, "win screen playing wrong track")
	_check(not music.stream.loop, "win jingle should not loop")

	win_screen.queue_free()
	await get_tree().physics_frame


# ---------------------------------------------------------- level 2 tests

# Instantiates the pendulum hall away from the level-1 geometry that the
# suite keeps loaded, and settles its player.
func _spawn_hall() -> Node3D:
	var hall: Node3D = load("res://levels/pendulum_hall.tscn").instantiate()
	hall.position = Vector3(300.0, 0.0, 0.0)
	add_child(hall)
	var hall_player: CharacterBody3D = hall.get_node("Player")
	for i in 60:
		await get_tree().physics_frame
		if hall_player.is_on_floor():
			break
	return hall


func _free_hall(hall: Node3D) -> void:
	hall.queue_free()
	await get_tree().physics_frame


func test_sprint_is_faster() -> void:
	Input.action_press("move_forward")
	for i in 15:
		await get_tree().physics_frame
	var walk_speed := Vector2(player.velocity.x, player.velocity.z).length()

	Input.action_press("sprint")
	for i in 15:
		await get_tree().physics_frame
	var sprint_speed := Vector2(player.velocity.x, player.velocity.z).length()
	Input.action_release("sprint")
	Input.action_release("move_forward")

	_check(absf(walk_speed - 5.0) < 0.5, "walk speed off: %f" % walk_speed)
	_check(sprint_speed > 6.5, "sprint not faster: %f" % sprint_speed)


func test_menu_has_level_entries() -> void:
	var menu: Control = load("res://ui/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().physics_frame

	var level1: Button = menu.get_node("Center/Panel/MenuItems/Level1Button")
	var level2: Button = menu.get_node("Center/Panel/MenuItems/Level2Button")
	_check(level1.text.contains("Sphinx"), "level 1 entry missing its name")
	_check(level2.text.contains("Pendulum"), "level 2 entry missing its name")

	menu.queue_free()
	await get_tree().physics_frame


func test_level_chain_scenes_exist() -> void:
	for scene_path in GameManager.LEVEL_SCENES:
		_check(ResourceLoader.exists(scene_path), "missing level scene: %s" % scene_path)
	_check(GameManager.LEVEL_SCENES.size() >= 2, "expected at least two levels")


func test_pendulum_kills_and_god_mode_spares() -> void:
	var hall := await _spawn_hall()
	var hall_player: CharacterBody3D = hall.get_node("Player")
	var pendulums := get_tree().get_nodes_in_group("pendulums")
	_check(pendulums.size() == 6, "expected 6 pendulums, found %d" % pendulums.size())

	hall_player.global_position = Vector3(300.0, 1.0, -20.0)
	await get_tree().physics_frame
	hall._on_trap_hit()
	var reset := false
	for i in 150:
		await get_tree().physics_frame
		if hall_player.global_position.z > 1.0 and not hall_player.is_dying():
			reset = true
			break
	_check(reset, "pendulum hit did not reset the player")

	GameManager.god_mode = true
	hall_player.global_position = Vector3(300.0, 1.0, -20.0)
	await get_tree().physics_frame
	hall._on_trap_hit()
	for i in 10:
		await get_tree().physics_frame
	_check(hall_player.global_position.z < -15.0, "god mode did not spare the player")
	GameManager.god_mode = false
	await _free_hall(hall)


func test_kill_plane_resets_fall() -> void:
	var hall := await _spawn_hall()
	var hall_player: CharacterBody3D = hall.get_node("Player")
	hall_player.global_position = Vector3(300.0, -10.0, -20.0)
	var reset := false
	for i in 120:
		await get_tree().physics_frame
		if hall_player.global_position.z > 1.0 and hall_player.global_position.y > -2.0 \
				and not hall_player.is_dying():
			reset = true
			break
	_check(reset, "kill plane did not reset the falling player")
	await _free_hall(hall)


func test_crack_tile_falls_and_respawns() -> void:
	var hall := await _spawn_hall()
	var tiles := get_tree().get_nodes_in_group("crack_tiles")
	_check(tiles.size() == 16, "expected 16 crack tiles, found %d" % tiles.size())

	var tile: StaticBody3D = tiles[0]
	var rest_y: float = tile.position.y
	tile._trigger()
	for i in 130:
		await get_tree().physics_frame
	_check(tile.position.y < rest_y - 1.0, "tile did not fall after trigger")

	for i in 240:
		await get_tree().physics_frame
		if is_equal_approx(tile.position.y, rest_y) and tile._armed:
			break
	_check(is_equal_approx(tile.position.y, rest_y), "tile did not respawn")
	_check(tile._armed, "tile not re-armed after respawn")
	await _free_hall(hall)


# --------------------------------------------------------- monument tests

func test_monument_and_exit_marker() -> void:
	_check(level.has_node("Monument/Sphinx"), "sphinx model missing")
	_check(level.has_node("Monument/Pyramid"), "pyramid model missing")
	_check(level.has_node("Monument/Doorway"), "dark exit opening missing")
	_check(level.has_node("Monument/ExitSign"), "green exit sign missing")

	var sign_pos: Vector3 = level.get_node("Monument/ExitSign").global_position
	var door_pos: Vector3 = level.get_node("Monument/Doorway").global_position
	_check(sign_pos.x > door_pos.x, "exit sign not in the right half of the opening")
	_check(sign_pos.y > door_pos.y, "exit sign not in the upper half of the opening")
