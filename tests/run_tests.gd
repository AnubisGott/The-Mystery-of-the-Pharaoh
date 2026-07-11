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
	# The headless window defaults to 100x100; pin it to the size the
	# spear pixel constants were tuned for (spears scale from it).
	get_window().size = Vector2i(1152, 648)

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
	# Give the grounded camera height a moment to converge after the
	# spawn drop; only then must it hold still through jumps and ducks.
	for i in 30:
		await get_tree().physics_frame
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
	var anim: AnimationPlayer = player.get_node("Visual/AnimationPlayer")
	_check(anim.current_animation == "Death_B",
			"head hit did not play the forward death clip: %s" % anim.current_animation)

	_check(await _await_death_reset(), "death sequence did not end in a reset")
	_check(anim.current_animation == "Idle",
			"pose not restored after reset: %s" % anim.current_animation)


func test_feet_hit_falls_backwards() -> void:
	await _place_on_path(10.0)
	level._on_player_hit(false)
	for i in 10:
		await get_tree().physics_frame

	_check(player.is_dying(), "player not in dying state after hit")
	var anim: AnimationPlayer = player.get_node("Visual/AnimationPlayer")
	_check(anim.current_animation == "Death_A",
			"feet hit did not play the backward death clip: %s" % anim.current_animation)

	_check(await _await_death_reset(), "death sequence did not end in a reset")
	_check(anim.current_animation == "Idle",
			"pose not restored after reset: %s" % anim.current_animation)


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


func test_escape_opens_pause_menu() -> void:
	var menu: CanvasLayer = level.get_node("PauseMenu")
	_check(not menu.visible, "pause menu visible before ESC")

	_press_key(KEY_ESCAPE)
	await _await_input_dispatch()
	_check(menu.visible, "ESC did not open the pause menu")
	_check(get_tree().paused, "ESC did not pause the game")
	var labels: Array[String] = []
	for button in menu.get_node("Root/Center/Panel/Items").get_children():
		if button is Button:
			labels.append(button.text)
	for expected in ["Resume", "Reset Level", "Main Menu", "Quit Game"]:
		_check(labels.has(expected), "pause menu misses entry: %s" % expected)

	# ESC again resumes; so does the Resume button.
	_press_key(KEY_ESCAPE)
	await _await_input_dispatch()
	_check(not menu.visible, "ESC did not close the pause menu")
	_check(not get_tree().paused, "ESC did not unpause the game")

	menu.open()
	_check(get_tree().paused, "open() did not pause")
	menu.get_node("Root/Center/Panel/Items/ResumeButton").pressed.emit()
	_check(not get_tree().paused, "Resume did not unpause")
	_check(not menu.visible, "Resume did not hide the menu")


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
	var trigger: float = spear.speed * Spear2D.WHOOSH_LEAD_TIME
	spear.position.x = _center_x() - trigger - 120.0
	spear._physics_process(1.0 / 60.0)
	_check(not spear._whoosh_played, "whoosh played too far from center")

	spear.position.x = _center_x() - trigger + 60.0
	spear._physics_process(1.0 / 60.0)
	_check(spear._whoosh_played, "whoosh not triggered near screen center")


func test_spear_flight_time_resolution_independent() -> void:
	layer.spawn_spear(false, true)
	var base := _last_spear()
	var base_time: float = (_center_x() - base.position.x) / base.speed

	# Twice as wide, same height: the reaction time must not grow.
	get_window().size = Vector2i(2304, 648)
	await get_tree().process_frame
	layer.reset_ramp()
	layer.spawn_spear(false, true)
	var wide := _last_spear()
	var wide_time: float = (get_viewport().get_visible_rect().size.x * 0.5 - wide.position.x) / wide.speed

	get_window().size = Vector2i(1152, 648)
	await get_tree().process_frame
	_check(absf(base_time - wide_time) < 0.02,
			"flight time differs: %.3f s vs %.3f s" % [base_time, wide_time])


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


func test_movement_plays_matching_clips() -> void:
	var anim: AnimationPlayer = player.get_node("Visual/AnimationPlayer")
	player.sprint_allowed = true  # Level 1 disables sprint; test the clip mapping

	Input.action_press("move_forward")
	for i in 10:
		await get_tree().physics_frame
	var walking := anim.current_animation

	Input.action_press("sprint")
	for i in 10:
		await get_tree().physics_frame
	var running := anim.current_animation
	Input.action_release("sprint")
	Input.action_release("move_forward")

	for i in 30:
		await get_tree().physics_frame
	var standing := anim.current_animation

	_check(walking == "Walking_A", "moving did not play the walk clip: %s" % walking)
	_check(running == "Running_A", "sprinting did not play the run clip: %s" % running)
	_check(standing == "Idle", "standing still did not return to idle: %s" % standing)


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
	player.sprint_allowed = true
	Input.action_press("move_forward")
	for i in 15:
		await get_tree().physics_frame
	var walk_speed := Vector2(player.velocity.x, player.velocity.z).length()

	Input.action_press("sprint")
	for i in 15:
		await get_tree().physics_frame
	var sprint_speed := Vector2(player.velocity.x, player.velocity.z).length()

	# With sprinting disabled (Level 1's default), Shift must not speed up.
	player.sprint_allowed = false
	for i in 15:
		await get_tree().physics_frame
	var blocked_speed := Vector2(player.velocity.x, player.velocity.z).length()
	Input.action_release("sprint")
	Input.action_release("move_forward")
	player.sprint_allowed = true

	_check(absf(walk_speed - 5.0) < 0.5, "walk speed off: %f" % walk_speed)
	_check(sprint_speed > 6.5, "sprint not faster: %f" % sprint_speed)
	_check(absf(blocked_speed - 5.0) < 0.5, "sprint not blocked when disallowed: %f" % blocked_speed)


func test_menu_has_level_entries() -> void:
	var menu: Control = load("res://ui/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().physics_frame

	var expected_names: Array[String] = ["Sphinx", "Pendulum", "Stairs",
			"Burial", "Slide", "Crocodiles", "Journey"]
	for i in expected_names.size():
		var button: Button = menu.get_node(
				"Center/Panel/MenuItems/Level%dButton" % (i + 1))
		_check(button.text.contains(expected_names[i]),
				"level %d entry missing its name" % (i + 1))

	menu.queue_free()
	await get_tree().physics_frame


func test_display_settings_cycle_and_persist() -> void:
	# Remember the player's settings; the test restores them at the end
	# (display changes are no-ops in headless runs, only state changes).
	var orig_fullscreen: bool = GameManager.fullscreen
	var orig_size: Vector2i = GameManager.window_size

	var sizes: Array[Vector2i] = GameManager.available_window_sizes()
	_check(not sizes.is_empty(), "no window size presets available")

	var menu: Control = load("res://ui/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().physics_frame

	var display_button: Button = menu.get_node("Center/Panel/MenuItems/DisplayButton")
	var size_button: Button = menu.get_node("Center/Panel/MenuItems/SizeButton")

	size_button.pressed.emit()
	_check(sizes.size() == 1 or GameManager.window_size != orig_size,
			"size button did not cycle the window size")
	_check(size_button.text.contains("%d x %d" % [GameManager.window_size.x, GameManager.window_size.y]),
			"size label does not show the current size")

	display_button.pressed.emit()
	_check(GameManager.fullscreen != orig_fullscreen, "display button did not toggle fullscreen")
	_check(size_button.disabled == GameManager.fullscreen,
			"size button enabled state does not follow fullscreen")

	GameManager.set_fullscreen(orig_fullscreen)
	GameManager.set_window_size(orig_size)
	menu.queue_free()
	await get_tree().physics_frame


func test_level1_intro_hands_off_to_gameplay() -> void:
	# The intro autoplay is gated off headless; drive it directly with a
	# short duration and check that gameplay starts afterwards.
	await level._play_intro(0.3)

	_check(player.is_physics_processing(), "player still frozen after intro")
	_check(get_viewport().get_camera_3d() == player.get_node("CameraPivot/CameraArm/Camera3D"),
			"player camera not current after intro")
	_check(not level._practice_timer.is_stopped(), "spear timers not started after intro")
	_check(not level._intro_running, "intro still flagged as running")

	# The suite runs without spear timers; stop them again.
	level._spear_timer.stop()
	level._practice_timer.stop()


func test_level2_intro_slows_and_restores_pendulums() -> void:
	var hall := await _spawn_hall()
	await hall._play_intro(0.3)

	for pendulum in get_tree().get_nodes_in_group("pendulums"):
		_check(is_equal_approx(pendulum.time_scale, 1.0),
				"pendulum speed not restored after intro")
	var hall_player: CharacterBody3D = hall.get_node("Player")
	_check(hall_player.is_physics_processing(), "hall player still frozen after intro")
	_check(get_viewport().get_camera_3d() == hall_player.get_node("CameraPivot/CameraArm/Camera3D"),
			"hall player camera not current after intro")
	await _free_hall(hall)


# ------------------------------------------------------------ stairs tests

func _spawn_stairs() -> Node3D:
	var stairs: Node3D = load("res://levels/stairs.tscn").instantiate()
	stairs.position = Vector3(600.0, 0.0, 0.0)
	add_child(stairs)
	var stairs_player: CharacterBody3D = stairs.get_node("Player")
	for i in 60:
		await get_tree().physics_frame
		if stairs_player.is_on_floor():
			break
	return stairs


func test_stairs_boulder_hit_kills_and_other_lane_misses() -> void:
	var stairs := await _spawn_stairs()
	var stairs_player: CharacterBody3D = stairs.get_node("Player")

	# A boulder rolling down another lane passes without harm.
	var missing: Node3D = stairs._spawn_boulder()
	missing.position = Vector3(1.4, 0.75, 0.0)
	missing.direction = Vector3(0, 0, 1)
	for i in 60:
		await get_tree().physics_frame
		if not is_instance_valid(missing) or missing.position.z > 4.5:
			break
	_check(not stairs_player.is_dying(), "boulder in another lane hit the player")

	# One in the player's lane kills.
	var boulder: Node3D = stairs._spawn_boulder()
	boulder.position = Vector3(0.0, 0.75, 0.0)
	boulder.direction = Vector3(0, 0, 1)
	var died := false
	for i in 90:
		await get_tree().physics_frame
		if stairs_player.is_dying():
			died = true
			break
	_check(died, "boulder in the player's lane did not kill")

	stairs.queue_free()
	await get_tree().physics_frame


func test_stairs_camera_follows_the_climb() -> void:
	var stairs := await _spawn_stairs()
	var stairs_player: CharacterBody3D = stairs.get_node("Player")

	# Halfway up the stairs the camera must ride at head height with the
	# player, not stay pinned at the valley height (it used to end up
	# under the stairs after ~30 m of climbing).
	stairs_player.global_position = stairs.to_global(
			Vector3(0, stairs._ramp_y(-42.0) + 1.0, -42.0))
	for i in 40:
		await get_tree().physics_frame
	var pivot: Node3D = stairs_player.get_node("CameraPivot")
	var pivot_above_feet: float = pivot.global_position.y \
			- (stairs_player.global_position.y - 0.9)
	_check(absf(pivot_above_feet - 1.55) < 0.3,
			"camera pivot not at head height on the stairs: %f" % pivot_above_feet)

	stairs.queue_free()
	await get_tree().physics_frame


func test_stairs_difficulty_ramps_with_height() -> void:
	var stairs := await _spawn_stairs()
	_check(is_equal_approx(stairs._spawn_interval(0.0), stairs.INTERVAL_EASY),
			"easy interval wrong")
	_check(is_equal_approx(stairs._spawn_interval(1.0), stairs.INTERVAL_HARD),
			"hard interval wrong")
	_check(stairs._spawn_interval(0.0) > stairs._spawn_interval(1.0) + 1.0,
			"boulder interval does not ramp up the stairs")

	var stairs_player: CharacterBody3D = stairs.get_node("Player")
	_check(stairs._progress() < 0.05, "progress not zero at the bottom")
	stairs_player.global_position = stairs.to_global(
			Vector3(0, stairs._ramp_y(-42.0) + 1.0, -42.0))
	_check(absf(stairs._progress() - 0.5) < 0.05, "progress wrong mid-climb")

	stairs.queue_free()
	await get_tree().physics_frame


func test_stairs_win_zone_at_top() -> void:
	var stairs := await _spawn_stairs()
	var win: Area3D = stairs.get_node("WinZone")
	var lp: Vector3 = stairs.to_local(win.global_position)
	_check(lp.y > stairs.TOP_Y and lp.y < stairs.TOP_Y + 3.0,
			"win zone not on the top platform")
	_check(lp.z < stairs.STAIRS_END_Z, "win zone not past the stairs")
	stairs.queue_free()
	await get_tree().physics_frame


func test_level3_intro_hands_off_to_gameplay() -> void:
	var stairs := await _spawn_stairs()
	await stairs._play_intro(0.3)
	var stairs_player: CharacterBody3D = stairs.get_node("Player")
	_check(stairs_player.is_physics_processing(), "stairs player still frozen after intro")
	_check(get_viewport().get_camera_3d() == stairs_player.get_node("CameraPivot/CameraArm/Camera3D"),
			"stairs player camera not current after intro")
	_check(not stairs._boulder_timer.is_stopped(), "boulder timer not started after intro")
	stairs.queue_free()
	await get_tree().physics_frame


func test_level_chain_scenes_exist() -> void:
	for scene_path in GameManager.LEVEL_SCENES:
		_check(ResourceLoader.exists(scene_path), "missing level scene: %s" % scene_path)
	_check(GameManager.LEVEL_SCENES.size() == 7, "expected the full seven levels")


# ---------------------------------------------------- burial chamber tests

func _spawn_burial() -> Node3D:
	var chamber: Node3D = load("res://levels/burial_chamber.tscn").instantiate()
	chamber.position = Vector3(900.0, 0.0, 0.0)
	add_child(chamber)
	var chamber_player: CharacterBody3D = chamber.get_node("Player")
	for i in 60:
		await get_tree().physics_frame
		if chamber_player.is_on_floor():
			break
	return chamber


func test_interact_action_is_f_and_e() -> void:
	var keys: Array[int] = []
	for event in InputMap.action_get_events("interact"):
		if event is InputEventKey:
			keys.append(event.physical_keycode)
	_check(keys.has(KEY_F), "interact not bound to F")
	_check(keys.has(KEY_E), "interact not bound to E")


func test_burial_bowls_open_the_door() -> void:
	var chamber := await _spawn_burial()
	_check(not chamber.door_open, "door open before the bowls are lit")

	chamber._bowls[0].interact()
	await get_tree().physics_frame
	_check(not chamber.door_open, "door opened after only one bowl")

	chamber._bowls[1].interact()
	for i in 150:
		await get_tree().physics_frame
	_check(chamber.door_open, "both bowls lit but the door stayed shut")
	_check(chamber._door.position.y < 0.0, "door slab did not sink away")

	chamber.queue_free()
	await get_tree().physics_frame


func test_burial_dials_open_the_floor() -> void:
	var chamber := await _spawn_burial()
	for dial in chamber._dials:
		_check(not chamber.floor_open, "floor opened before all dials were turned")
		dial.interact()
		await get_tree().physics_frame

	for i in 160:
		await get_tree().physics_frame
	_check(chamber.floor_open, "all dials turned but the floor stayed shut")
	_check(absf(chamber._pit_slabs[0].position.x) > 8.0, "pit slab did not slide away")

	var end_zone: Area3D = chamber.get_node("EndZone")
	_check(chamber.to_local(end_zone.global_position).y < -8.0,
			"end zone not down in the pit")

	chamber.queue_free()
	await get_tree().physics_frame


func test_level4_intro_hands_off_to_gameplay() -> void:
	var chamber := await _spawn_burial()
	await chamber._play_intro(0.3)
	var chamber_player: CharacterBody3D = chamber.get_node("Player")
	_check(chamber_player.is_physics_processing(), "chamber player still frozen after intro")
	_check(get_viewport().get_camera_3d() == chamber_player.get_node("CameraPivot/CameraArm/Camera3D"),
			"chamber player camera not current after intro")
	chamber.queue_free()
	await get_tree().physics_frame


# -------------------------------------------------------------- slide tests

func _spawn_slide() -> Node3D:
	var slide: Node3D = load("res://levels/slide.tscn").instantiate()
	slide.position = Vector3(1200.0, 0.0, 0.0)
	add_child(slide)
	var slide_player: CharacterBody3D = slide.get_node("Player")
	for i in 60:
		await get_tree().physics_frame
		if slide_player.is_on_floor():
			break
	return slide


func test_slide_carries_the_player_down() -> void:
	var slide := await _spawn_slide()
	var slide_player: CharacterBody3D = slide.get_node("Player")
	for i in 60:
		await get_tree().physics_frame
	var lp: Vector3 = slide.to_local(slide_player.global_position)
	_check(lp.z < -1.0, "slide did not carry the player: z=%f" % lp.z)
	_check(lp.y < 0.5, "player did not descend the chute: y=%f" % lp.y)
	slide.queue_free()
	await get_tree().physics_frame


func test_slide_obstacle_kills() -> void:
	var slide := await _spawn_slide()
	var slide_player: CharacterBody3D = slide.get_node("Player")
	# Drop the player right before the first block (it sits at x=-0.9, z=-16).
	slide_player.global_position = slide.to_global(
			Vector3(-0.9, slide._ramp_y(-13.0) + 1.0, -13.0))
	var died := false
	for i in 120:
		await get_tree().physics_frame
		if slide_player.is_dying():
			died = true
			break
	_check(died, "sliding into the block did not kill")
	slide.queue_free()
	await get_tree().physics_frame


func test_slide_ends_in_water() -> void:
	var slide := await _spawn_slide()
	var end_zone: Area3D = slide.get_node("EndZone")
	var lp: Vector3 = slide.to_local(end_zone.global_position)
	_check(lp.y < slide.END_Y - 4.0, "water end zone not below the chute exit")
	_check(lp.z < slide.SLIDE_END_Z, "water end zone not past the chute exit")
	slide.queue_free()
	await get_tree().physics_frame


func test_level5_intro_hands_off_to_gameplay() -> void:
	var slide := await _spawn_slide()
	slide._sliding = false
	await slide._play_intro(0.3)
	_check(slide._sliding, "sliding not enabled after intro")
	var slide_player: CharacterBody3D = slide.get_node("Player")
	_check(get_viewport().get_camera_3d() == slide_player.get_node("CameraPivot/CameraArm/Camera3D"),
			"slide player camera not current after intro")
	slide.queue_free()
	await get_tree().physics_frame


# --------------------------------------------------------- crocodile tests

func _spawn_crocs() -> Node3D:
	var crocs: Node3D = load("res://levels/crocodiles.tscn").instantiate()
	crocs.position = Vector3(1500.0, 0.0, 0.0)
	add_child(crocs)
	var crocs_player: CharacterBody3D = crocs.get_node("Player")
	for i in 60:
		await get_tree().physics_frame
		if crocs_player.is_on_floor():
			break
	return crocs


func test_croc_backs_hold_the_player() -> void:
	var crocs := await _spawn_crocs()
	var crocs_player: CharacterBody3D = crocs.get_node("Player")
	# Freeze every croc surfaced, then stand on the first one.
	for croc in get_tree().get_nodes_in_group("crocodiles"):
		croc.frozen = true
	crocs_player.global_position = crocs.to_global(
			crocs._croc_positions[0] + Vector3(0, 1.2, 0))
	for i in 40:
		await get_tree().physics_frame
	_check(not crocs_player.is_dying(), "standing on a surfaced croc killed the player")
	_check(crocs_player.is_on_floor(), "player does not stand on the croc's back")
	crocs.queue_free()
	await get_tree().physics_frame


func test_croc_water_kills_and_resets() -> void:
	var crocs := await _spawn_crocs()
	var crocs_player: CharacterBody3D = crocs.get_node("Player")
	crocs_player.global_position = crocs.to_global(Vector3(3.0, -0.2, -30.0))
	var died := false
	for i in 90:
		await get_tree().physics_frame
		if crocs_player.is_dying():
			died = true
			break
	_check(died, "falling into the Nile did not kill")
	crocs.queue_free()
	await get_tree().physics_frame


func test_croc_gaps_widen_along_the_river() -> void:
	var crocs := await _spawn_crocs()
	var positions: Array[Vector3] = crocs._croc_positions
	var first_gap: float = positions[0].z - positions[1].z
	var last_gap: float = positions[positions.size() - 2].z - positions[positions.size() - 1].z
	_check(last_gap > first_gap + 1.0,
			"croc gaps do not widen: %f vs %f" % [first_gap, last_gap])
	var end_zone: Area3D = crocs.get_node("EndZone")
	_check(crocs.to_local(end_zone.global_position).z < positions[positions.size() - 1].z,
			"boat end zone not past the last crocodile")
	crocs.queue_free()
	await get_tree().physics_frame


func test_level6_intro_hands_off_to_gameplay() -> void:
	var crocs := await _spawn_crocs()
	await crocs._play_intro(0.3)
	var crocs_player: CharacterBody3D = crocs.get_node("Player")
	_check(crocs_player.is_physics_processing(), "crocs player still frozen after intro")
	_check(get_viewport().get_camera_3d() == crocs_player.get_node("CameraPivot/CameraArm/Camera3D"),
			"crocs player camera not current after intro")
	crocs.queue_free()
	await get_tree().physics_frame


func test_credits_scene_has_rolling_credits() -> void:
	var credits: Node3D = load("res://levels/nile_credits.tscn").instantiate()
	credits.position = Vector3(1800.0, 0.0, 0.0)
	add_child(credits)
	await get_tree().physics_frame
	_check(credits.has_node("Boat"), "credits scene misses the steamboat")
	_check(credits._scroll != null and credits._scroll.get_child_count() > 5,
			"credits scroll has no entries")
	var y_before: float = credits._scroll.position.y
	for i in 30:
		await get_tree().physics_frame
	_check(credits._scroll.position.y < y_before, "credits do not scroll upward")
	credits.queue_free()
	await get_tree().physics_frame


func test_pendulum_kills_and_god_mode_spares() -> void:
	var hall := await _spawn_hall()
	var hall_player: CharacterBody3D = hall.get_node("Player")
	var pendulums := get_tree().get_nodes_in_group("pendulums")
	_check(pendulums.size() == 9, "expected 9 pendulums, found %d" % pendulums.size())

	# A pendulum too close to a corner carves its wall pocket into the
	# corner mouth and blocks the turn.
	for data in hall.PENDULUM_DS:
		for corner_d in hall.CORNER_DS:
			_check(absf(data[0] - corner_d) >= 3.5,
					"pendulum at d=%s too close to corner at d=%s" % [data[0], corner_d])

	# Every hazard must lie inside the corridor (regression: a stale
	# leg lookup once placed late hazards beyond the last corner).
	var hazards := pendulums + get_tree().get_nodes_in_group("crack_tiles")
	for hazard in hazards:
		var local: Vector3 = hazard.global_position - hall.position
		var best := 1e9
		for i in range(hall.LEGS.size()):
			var origin: Vector3 = hall.LEGS[i]["origin"]
			var dir: Vector3 = hall.LEGS[i]["dir"]
			var length: float = (hall.CORNER_DS[i] if i < hall.CORNER_DS.size() else hall.END_D) \
					- (0.0 if i == 0 else hall.CORNER_DS[i - 1])
			var u: float = clampf((local - origin).dot(dir), 0.0, length)
			var closest: Vector3 = origin + dir * u
			best = minf(best, Vector2(local.x - closest.x, local.z - closest.z).length())
		_check(best < 2.3, "hazard at %s lies %f m outside the corridor" % [hazard.global_position, best])

	hall_player.global_position = Vector3(300.0, 1.0, -12.0)
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
	hall_player.global_position = Vector3(300.0, 1.0, -12.0)
	await get_tree().physics_frame
	hall._on_trap_hit()
	for i in 10:
		await get_tree().physics_frame
	_check(hall_player.global_position.z < -8.0, "god mode did not spare the player")
	GameManager.god_mode = false
	await _free_hall(hall)


func test_yaw_limited_outdoors_free_indoors() -> void:
	# A hard mouse swipe to the right, applied to both players.
	player._apply_look(Vector2(4000.0, 0.0))
	_check(absf(player.rotation.y) <= deg_to_rad(45.5),
			"level 1 yaw not clamped: %f" % player.rotation.y)
	player._apply_look(Vector2(-4000.0, 0.0))

	var hall := await _spawn_hall()
	var hall_player: CharacterBody3D = hall.get_node("Player")
	hall_player._apply_look(Vector2(4000.0, 0.0))
	_check(absf(hall_player.rotation.y) > deg_to_rad(50.0),
			"level 2 yaw unexpectedly clamped: %f" % hall_player.rotation.y)
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


func test_pendulum_speeds_random_per_run() -> void:
	var hall := await _spawn_hall()
	var pendulums := get_tree().get_nodes_in_group("pendulums")
	var before: Array = []
	var all_in_range := true
	for p in pendulums:
		before.append(p.period)
		if p.period < p.MIN_PERIOD or p.period > p.MAX_PERIOD:
			all_in_range = false
	_check(all_in_range, "pendulum period outside allowed range")

	var distinct := {}
	for value in before:
		distinct[value] = true
	_check(distinct.size() > 1, "all pendulums share one speed")

	# Dying re-rolls every speed.
	hall._on_trap_hit()
	for i in 150:
		await get_tree().physics_frame
		if not hall.get_node("Player").is_dying():
			break
	var changed := false
	for i in range(pendulums.size()):
		if not is_equal_approx(pendulums[i].period, before[i]):
			changed = true
	_check(changed, "speeds not re-rolled after death")
	await _free_hall(hall)


func test_crack_tile_stays_down_until_death() -> void:
	var hall := await _spawn_hall()
	var tiles := get_tree().get_nodes_in_group("crack_tiles")
	_check(tiles.size() == 30, "expected 30 crack tiles, found %d" % tiles.size())

	var tile: StaticBody3D = tiles[0]
	var rest_y: float = tile.position.y
	tile._trigger()
	for i in 130:
		await get_tree().physics_frame
	_check(tile.position.y < rest_y - 1.0, "tile did not fall after trigger")

	# No automatic respawn: the tile stays down.
	for i in 120:
		await get_tree().physics_frame
	_check(tile.position.y < rest_y - 1.0, "tile came back without a death")

	# Dying restores every tile.
	hall._on_trap_hit()
	for i in 150:
		await get_tree().physics_frame
		if is_equal_approx(tile.position.y, rest_y) and tile._armed:
			break
	_check(is_equal_approx(tile.position.y, rest_y), "tile not restored after death")
	_check(tile._armed, "tile not re-armed after death")
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
