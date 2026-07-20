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
	# Playing entries first, then a divider, then the ways out of the level:
	# Resume, Reset Level | Main Menu, Options, Quit Game.
	var order: Array[String] = []
	for button in menu.get_node("Root/Center/Panel/Items").get_children():
		if button is Button:
			order.append(button.name)
	_check(order == ["ResumeButton", "ResetButton", "MenuButton", "OptionsButton",
			"QuitButton"], "pause menu entries out of order: %s" % [order])
	_check(menu.get_node_or_null("Root/Center/Panel/Items/Separator") != null,
			"the pause menu has no divider between staying and leaving")
	# The "Paused" title reads as a header, not one more entry to tap.
	var pause_title: Label = menu.get_node("Root/Center/Panel/Items/Title")
	_check(pause_title.has_theme_color_override("font_color"),
			"the Paused title is not coloured apart from the entries")

	# Options are reachable from the pause menu too.
	menu.get_node("Root/Center/Panel/Items/OptionsButton").pressed.emit()
	_check(menu.get_node("Root/Center/Panel/OptionsItems").visible,
			"pause options panel did not open")
	menu.get_node("Root/Center/Panel/OptionsItems/BackButton").pressed.emit()
	_check(menu.get_node("Root/Center/Panel/Items").visible,
			"pause options back did not return")

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


# A burst of taps must not survive a scene change: flush_input drops every
# held or buffered action, so nothing replays into the next level.
func test_flush_input_drops_held_actions() -> void:
	Input.action_press("jump")
	Input.action_press("move_forward")
	await get_tree().physics_frame
	_check(Input.is_action_pressed("jump"), "could not hold an action to flush")
	GameManager.flush_input()
	_check(not Input.is_action_pressed("jump"), "flush_input left jump held")
	_check(not Input.is_action_pressed("move_forward"), "flush_input left move_forward held")


# Phone menu buttons carry a thumb-sized font, not the desktop's small one.
func test_touch_menu_buttons_are_enlarged() -> void:
	var box := VBoxContainer.new()
	var button := Button.new()
	box.add_child(button)
	add_child(box)
	GameManager.scale_menu_for_touch(box, 2.0)
	_check(button.get_theme_font_size("font_size") >= 50,
			"touch menu font too small: %d" % button.get_theme_font_size("font_size"))
	_check(button.custom_minimum_size.y >= 100.0,
			"touch menu button too short: %.0f" % button.custom_minimum_size.y)
	box.queue_free()
	await get_tree().physics_frame


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
	var toggle: Button = menu.get_node("Center/Panel/OptionsItems/MusicButton")
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
	# AudioStreamWAV has loop_mode, not the `loop` of MP3/Ogg streams - reading
	# `loop` here errors out and yields null, which quietly satisfied the old
	# assertion instead of checking anything.
	_check(music.stream.loop_mode == AudioStreamWAV.LOOP_DISABLED,
			"win jingle should not loop")

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

	# Top level: Select Level, Options, Quit - the levels live one step in.
	_check(menu.get_node("Center/Panel/MenuItems").visible, "the top level menu is hidden")
	_check(not menu.get_node("Center/Panel/LevelItems").visible,
			"the level list shows before Select Level is pressed")

	menu.get_node("Center/Panel/MenuItems/SelectLevelButton").pressed.emit()
	_check(menu.get_node("Center/Panel/LevelItems").visible, "Select Level did not open the list")
	_check(not menu.get_node("Center/Panel/MenuItems").visible,
			"the top level stayed visible under the level list")

	# The six played levels; the seventh is the credits roll and is not
	# offered here - it has its own entry on the top level.
	var expected_names: Array[String] = ["Sphinx", "Pendulum", "Stairs",
			"Burial", "Slide", "Crocodiles"]
	for i in expected_names.size():
		var button: Button = menu.get_node(
				"Center/Panel/LevelItems/Level%dButton" % (i + 1))
		_check(button.text.contains(expected_names[i]),
				"level %d entry missing its name" % (i + 1))
	_check(menu.level_buttons.size() == expected_names.size(),
			"the level list offers %d entries, want %d"
			% [menu.level_buttons.size(), expected_names.size()])
	_check(menu.get_node_or_null("Center/Panel/LevelItems/Level7Button") == null,
			"the credits are still listed as a level")

	# ...and Back returns to the top level.
	menu.get_node("Center/Panel/LevelItems/LevelBackButton").pressed.emit()
	_check(menu.get_node("Center/Panel/MenuItems").visible, "Back did not return to the top level")
	_check(not menu.get_node("Center/Panel/LevelItems").visible,
			"the level list stayed open after Back")

	var version: Label = menu.get_node("VersionLabel")
	_check(version.text == "v" + str(ProjectSettings.get_setting(
			"application/config/version", "?")),
			"version label does not show the project version")

	# The credits sit up front, under Options and above Quit: the boat trip
	# home can be watched without playing the game through first.
	var top_entries: Array[String] = []
	for child in menu.get_node("Center/Panel/MenuItems").get_children():
		if child is Button:
			top_entries.append(child.name)
	_check(top_entries == ["SelectLevelButton", "OptionsButton", "CreditsButton",
			"QuitButton"], "the top menu entries are not in order: %s" % [top_entries])
	_check(menu.credits_button.text == "Credits",
			"the credits entry is not labelled: %s" % menu.credits_button.text)
	_check(menu._credits_level() == GameManager.LEVEL_SCENES.size() - 1,
			"the credits entry does not start the last level")
	_check(GameManager.LEVEL_SCENES[menu._credits_level()] == "res://levels/nile_credits.tscn",
			"the last level is not the credits scene")
	# ...and it says so in every language.
	var previous_locale: String = TranslationServer.get_locale()
	for entry in GameManager.LANGUAGES:
		TranslationServer.set_locale(entry[0])
		_check(not tr("Credits").is_empty(), "no credits label in %s" % entry[0])
	TranslationServer.set_locale("de")
	_check(tr("Credits") == "Abspann", "the credits entry is not translated")
	TranslationServer.set_locale(previous_locale)

	# The Options button swaps to the options panel and back.
	menu.get_node("Center/Panel/MenuItems/OptionsButton").pressed.emit()
	_check(menu.get_node("Center/Panel/OptionsItems").visible, "options panel did not open")
	_check(not menu.get_node("Center/Panel/MenuItems").visible, "menu stayed visible under options")
	_check(menu.get_node("Center/Panel/OptionsItems/SoundSlider") != null, "sound slider missing")
	_check(menu.get_node("Center/Panel/OptionsItems/MusicSlider") != null, "music slider missing")
	# The options title is a header, coloured apart from the buttons below it.
	var options_title: Label = menu.get_node("Center/Panel/OptionsItems/OptionsTitle")
	_check(options_title.has_theme_color_override("font_color"),
			"the options title is not coloured as a header")
	menu.get_node("Center/Panel/OptionsItems/BackButton").pressed.emit()
	_check(menu.get_node("Center/Panel/MenuItems").visible, "back did not return to the menu")

	# The two sliders drive their own buses (and are restored after).
	var orig_sound: float = GameManager.sound_volume
	var orig_music: float = GameManager.music_volume
	menu.get_node("Center/Panel/OptionsItems/SoundSlider").value = 50.0
	_check(absf(GameManager.sound_volume - 0.5) < 0.01, "slider did not set the sound volume")
	_check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Sfx"))
			- linear_to_db(0.5)) < 0.1, "Sfx bus not at half loudness")
	menu.get_node("Center/Panel/OptionsItems/MusicSlider").value = 30.0
	_check(absf(GameManager.music_volume - 0.3) < 0.01, "slider did not set the music volume")
	_check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
			- linear_to_db(0.3)) < 0.1, "Music bus not at the set loudness")
	_check(GameManager._music_player.bus == "Music", "music player not on the Music bus")
	GameManager.set_sound_volume(orig_sound)
	GameManager.set_music_volume(orig_music)

	menu.queue_free()
	await get_tree().physics_frame


func test_display_settings_cycle_and_persist() -> void:
	# Remember the player's settings; the test restores them at the end
	# (display changes are no-ops in headless runs, only state changes).
	var orig_fullscreen: bool = GameManager.fullscreen
	var orig_size: Vector2i = GameManager.window_size
	# The saved settings may say fullscreen (the size label then reads
	# "Desktop"); the cycling checks below need windowed mode.
	GameManager.set_fullscreen(false)

	var sizes: Array[Vector2i] = GameManager.available_window_sizes()
	_check(not sizes.is_empty(), "no window size presets available")

	var menu: Control = load("res://ui/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().physics_frame

	var display_button: Button = menu.get_node("Center/Panel/OptionsItems/DisplayButton")
	var size_button: Button = menu.get_node("Center/Panel/OptionsItems/SizeButton")

	size_button.pressed.emit()
	_check(sizes.size() == 1 or GameManager.window_size != orig_size,
			"size button did not cycle the window size")
	_check(size_button.text.contains("%d x %d" % [GameManager.window_size.x, GameManager.window_size.y]),
			"size label does not show the current size")

	display_button.pressed.emit()
	_check(GameManager.fullscreen, "display button did not toggle fullscreen")
	_check(size_button.disabled == GameManager.fullscreen,
			"size button enabled state does not follow fullscreen")

	GameManager.set_fullscreen(orig_fullscreen)
	GameManager.set_window_size(orig_size)
	menu.queue_free()
	await get_tree().physics_frame


func test_no_spears_in_the_sphinx_shelter() -> void:
	# On the open path the spear timer spawns as usual...
	player.global_position = Vector3(0.1, 1.0, 0.0)
	await get_tree().physics_frame
	level._on_spear_timer_timeout()
	_check(layer.has_active_spears(), "no spear spawned on the open path")
	layer._clear_spears()

	# ...but between the sphinx's legs the player is sheltered.
	player.global_position = Vector3(0.1, 1.0, -90.0)
	await get_tree().physics_frame
	level._on_spear_timer_timeout()
	level._on_practice_timer_timeout()
	_check(not layer.has_active_spears(), "spears spawned inside the sphinx shelter")

	# The handlers rearm the timers; keep them silent for the other tests.
	level._spear_timer.stop()
	level._practice_timer.stop()


func test_touch_mode_level1_auto_runs() -> void:
	_check(level.get_node_or_null("TouchControls") == null,
			"touch controls present in desktop mode")

	GameManager.touch_mode = true
	level._setup_touch_mode()
	var touch: Node = level.get_node_or_null("TouchControls")
	_check(touch != null, "touch controls missing in touch mode")
	var actions: Array[String] = []
	if touch:
		for child in touch.get_children():
			if child is TouchScreenButton and child.action != "":
				actions.append(child.action)
	_check(actions.has("jump") and actions.has("duck"),
			"jump/duck buttons missing (found: %s)" % [actions])
	_check(not level.get_node("ControlsHint").visible,
			"keyboard hints still visible in touch mode")

	# The auto-run driver must carry the player down the path by itself.
	var z_start: float = player.global_position.z
	for i in 60:
		await get_tree().physics_frame
	_check(player.global_position.z < z_start - 1.0,
			"auto-run did not move the player (z %.2f -> %.2f)"
			% [z_start, player.global_position.z])

	# Back to desktop mode for the rest of the suite.
	GameManager.touch_mode = false
	Input.action_release("move_forward")
	if touch:
		touch.free()
	level.get_node("ControlsHint").visible = true
	await get_tree().physics_frame


func test_touch_mode_stairs_dodge_two_lanes() -> void:
	# On a phone the climb is dodged left and right, on two lanes - and a
	# wave is always a single boulder, so a free side always remains.
	GameManager.touch_mode = true
	var stairs := await _spawn_stairs()
	stairs._boulder_timer.stop()

	var actions: Array[String] = _touch_actions(stairs)
	_check(actions.has("move_left") and actions.has("move_right"),
			"the stairs have no left/right buttons (found: %s)" % [actions])
	_check(not actions.has("jump") and not actions.has("duck"),
			"the stairs still offer jump/duck on a phone")

	_check(stairs._lanes().size() == 2,
			"the phone climb does not start on two lanes")
	_check(stairs._boulder_radius() > stairs.Boulder.RADIUS,
			"the two-lane boulders are not the fat ones")

	# The phone climb is the longer one, and the top of the staircase - the
	# platform, the doorway and the win zone - moved up with it.
	_check(stairs._end_z() < stairs.STAIRS_END_Z - 30.0,
			"the phone staircase is no longer than the desktop one (%.0f)" % stairs._end_z())
	var stairs_win: Area3D = stairs.get_node("WinZone")
	var win_local: Vector3 = stairs.to_local(stairs_win.global_position)
	_check(win_local.z < stairs._end_z(),
			"the win zone stayed at the old top of the stairs (z %.0f)" % win_local.z)
	_check(win_local.y > stairs._top_y() and win_local.y < stairs._top_y() + 3.0,
			"the win zone is not on the new top platform (y %.1f)" % win_local.y)

	# The dodge is the quick move: half a second has to cover the whole
	# lane change, boulders come down fast.
	var stairs_player: CharacterBody3D = stairs.get_node("Player")
	_check(stairs_player.strafe_multiplier > 1.0,
			"the phone stairs dodge at plain walking speed")
	var lanes: Array = stairs._lanes()
	var here: Vector3 = stairs.to_local(stairs_player.global_position)
	stairs_player.global_position = stairs.to_global(Vector3(lanes[0], here.y, here.z))
	await get_tree().physics_frame
	Input.action_press("move_right")
	for i in 30:   # 0.5 s
		await get_tree().physics_frame
	Input.action_release("move_right")
	var landed_x: float = stairs.to_local(stairs_player.global_position).x
	_check(landed_x >= lanes[1] - 0.2,
			"half a second of dodging got from lane %.1f only to %.1f, not %.1f"
			% [lanes[0], landed_x, lanes[1]])

	# Fifty waves down here, never a twin: two lanes must always leave a way
	# past, and a twin would wall both of them off.
	for i in 50:
		for boulder in get_tree().get_nodes_in_group("boulders"):
			boulder.queue_free()
		await get_tree().physics_frame
		stairs._on_boulder_timer_timeout()
		stairs._boulder_timer.stop()
		var wave: int = get_tree().get_nodes_in_group("boulders").size()
		if wave > 1:
			_check(false, "a wave of %d boulders blocked both lanes" % wave)
			break

	for boulder in get_tree().get_nodes_in_group("boulders"):
		boulder.queue_free()

	# Past the middle of the climb the third lane opens, and with it the
	# desktop's twin waves - on leaner boulders, three of which the corridor
	# has room for side by side.
	var half_z: float = lerpf(stairs.STAIRS_START_Z, stairs._end_z(),
			stairs.THREE_LANE_PROGRESS_TOUCH + 0.1)
	stairs_player.global_position = stairs.to_global(
			Vector3(0.0, stairs._ramp_y(half_z) + 1.0, half_z))
	await get_tree().physics_frame
	_check(stairs._lanes().size() == 3,
			"the second half of the phone climb did not open the third lane")
	_check(is_equal_approx(stairs._boulder_radius(), stairs.Boulder.RADIUS),
			"the three-lane boulders are still the fat two-lane ones")

	# A hundred waves up here: twins do turn up, and never a wave that fills
	# all three lanes - there is always a lane to dodge into.
	var twins := 0
	var lanes_x: Array = stairs._lanes()
	for i in 100:
		for boulder in get_tree().get_nodes_in_group("boulders"):
			boulder.queue_free()
		await get_tree().physics_frame
		stairs._on_boulder_timer_timeout()
		stairs._boulder_timer.stop()
		var wave: Array = get_tree().get_nodes_in_group("boulders")
		if wave.size() > 2:
			_check(false, "a wave of %d boulders walled off all three lanes" % wave.size())
			break
		if wave.size() == 2:
			twins += 1
			# ...and the two sit in different lanes, so the third is free.
			_check(absf(wave[0].position.x - wave[1].position.x) > 0.5,
					"a twin wave rolled two boulders down the same lane")
			var free_lanes: Array = lanes_x.filter(func(x: float) -> bool:
				for boulder in wave:
					if absf(boulder.position.x - x) < 0.5:
						return false
				return true)
			_check(free_lanes.size() >= 1, "a twin wave left no lane open")
	_check(twins > 5, "the three-lane climb rolled %d twin waves in a hundred" % twins)

	for boulder in get_tree().get_nodes_in_group("boulders"):
		boulder.queue_free()

	# And the added stretch is real staircase: set down near the new top, he
	# stands on it instead of dropping through the world.
	var high_z: float = stairs._end_z() + 8.0
	stairs_player.global_position = stairs.to_global(
			Vector3(0.0, stairs._ramp_y(high_z) + 1.0, high_z))
	for i in 40:
		await get_tree().physics_frame
	_check(stairs_player.is_on_floor(), "no steps under the extended climb at z=%.0f" % high_z)
	_check(not stairs_player.is_dying(), "the extended climb killed the player on its own")

	GameManager.touch_mode = false
	Input.action_release("move_forward")
	stairs.queue_free()
	await get_tree().physics_frame


func test_touch_mode_hall_and_chamber_controls() -> void:
	GameManager.touch_mode = true

	# Level 2: forward/back/jump, and the adventurer turns himself into
	# each leg of the corridor (there is no mouse to look with).
	var hall := await _spawn_hall()
	var hall_actions: Array[String] = _touch_actions(hall)
	for action in ["move_forward", "move_back", "jump"]:
		_check(hall_actions.has(action), "hall touch button for %s missing" % action)
	var yaw_leg2: float = hall.LEGS[2]["yaw"]
	var hall_player: CharacterBody3D = hall.get_node("Player")
	hall_player.global_position = hall.to_global(Vector3(-50.0, 1.0, -20.0))
	for i in 40:
		await get_tree().physics_frame
	_check(absf(angle_difference(hall_player.rotation.y, yaw_leg2)) < 0.2,
			"the adventurer did not face along corridor leg 2 (yaw %.2f, want %.2f)"
			% [hall_player.rotation.y, yaw_leg2])

	# And the corners walk themselves: holding forward alone, from the
	# straight before the first turn, has to carry him around it.
	hall_player.global_position = hall.to_global(Vector3(0.0, 1.0, -28.0))
	hall_player.velocity = Vector3.ZERO
	hall_player.rotation.y = 0.0
	hall_player._yaw = 0.0
	for i in 10:
		await get_tree().physics_frame
	Input.action_press("move_forward")
	for i in 150:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	var turned: Vector3 = hall.to_local(hall_player.global_position)
	_check(turned.x < -4.0,
			"the adventurer did not round corner 1 on his own (x %.1f)" % turned.x)
	_check(turned.y > -2.0, "the adventurer fell while rounding corner 1")

	# The finale's last hole is jumped off a crumbling tile at a walk (no
	# sprint key on a phone), so its landing reaches further back.
	var touch_floor: Array = hall._floor_segments()
	var desktop_floor: Array = hall.FLOOR_D_SEGMENTS
	var touch_last: float = touch_floor[touch_floor.size() - 1][0]
	var desktop_last: float = desktop_floor[desktop_floor.size() - 1][0]
	_check(is_equal_approx(desktop_last - touch_last, hall.LAST_HOLE_SHRINK_TOUCH),
			"the touch finale's last hole was not shortened (%.1f vs %.1f)"
			% [touch_last, desktop_last])
	_check(is_equal_approx(desktop_last, 160.0),
			"the desktop finale's last hole moved: %.1f" % desktop_last)
	await _free_hall(hall)

	# Level 4: direction pad plus one Use button.
	var chamber: Node3D = load("res://levels/burial_chamber.tscn").instantiate()
	chamber.intro_enabled = false
	chamber.position = Vector3(0.0, 0.0, 900.0)
	add_child(chamber)
	await get_tree().physics_frame
	var chamber_actions: Array[String] = _touch_actions(chamber)
	for action in ["move_forward", "move_back", "interact"]:
		_check(chamber_actions.has(action), "chamber touch button for %s missing" % action)
	_check(chamber._touch_turn_left != null and chamber._touch_turn_right != null,
			"the chamber direction pad has no turn buttons")

	# With no pad button held the adventurer must not spin on his own.
	var chamber_player: CharacterBody3D = chamber.get_node("Player")
	var yaw_before: float = chamber_player.rotation.y
	for i in 20:
		chamber._turn_with_pad(1.0 / 60.0)
	_check(absf(angle_difference(chamber_player.rotation.y, yaw_before)) < 0.01,
			"the direction pad turned the adventurer with nothing pressed")

	# The Use prompt is the phone's only cue that a thing can be used, so
	# its layer must survive touch mode - only the keyboard hint goes.
	_check(chamber.get_node("ControlsHint").visible,
			"touch mode hid the layer the Use prompt lives in")
	_check(not chamber.get_node("ControlsHint/Root/HintLabel").visible,
			"the keyboard hint is still shown on a phone")
	var usable: Node3D = null
	for node in get_tree().get_nodes_in_group("interactables"):
		if chamber.is_ancestor_of(node) and node.can_interact():
			usable = node
			break
	_check(usable != null, "the chamber has nothing to use")
	if usable != null:
		chamber_player.global_position = usable.global_position + Vector3.UP * 1.2 \
				+ Vector3.RIGHT * 0.8
		for i in 4:
			await get_tree().physics_frame
		_check(chamber.prompt_label.visible,
				"no Use prompt next to a usable thing on a phone")
		_check(chamber.prompt_label.text.begins_with(tr("USE")),
				"the touch Use prompt does not lead with the button's word: '%s'"
				% chamber.prompt_label.text)

	GameManager.touch_mode = false
	chamber.queue_free()
	await get_tree().physics_frame


# The finale's last hole has to go down at a walk: a phone has no sprint
# key, and the take-off is a crumbling tile. Walk him at it and jump.
func test_touch_hall_last_hole_clears_at_a_walk() -> void:
	GameManager.touch_mode = true
	var hall := await _spawn_hall()
	var hall_player: CharacterBody3D = hall.get_node("Player")

	# Two pendulums guard that stretch, and their speeds are rolled fresh
	# every run: one of them swinging into the take-off is a death this test
	# is not about. Clear the blades, keep the crumbling tiles.
	for pendulum in get_tree().get_nodes_in_group("pendulums"):
		if hall.is_ancestor_of(pendulum):
			pendulum.queue_free()
	await get_tree().physics_frame

	# Onto the tile field before the hole, facing up the last leg.
	hall_player.global_position = hall._center_at_d(151.0) + Vector3.UP * 1.2
	hall_player.velocity = Vector3.ZERO
	for i in 10:
		await get_tree().physics_frame

	Input.action_press("move_forward")
	var jumped := false
	var d := 0.0
	for i in 240:
		await get_tree().physics_frame
		d = hall._d_at(hall.to_local(hall_player.global_position))
		if jumped:
			Input.action_release("jump")
		elif d > 155.4 and hall_player.is_on_floor():
			Input.action_press("jump")
			jumped = true
		if d > 162.0 or hall_player.is_dying():
			break
	Input.action_release("move_forward")
	Input.action_release("jump")

	var landed: Vector3 = hall.to_local(hall_player.global_position)
	_check(jumped, "the walk never reached the last hole (d=%.1f)" % d)
	_check(not hall_player.is_dying(), "the last hole killed the walking adventurer")
	_check(d > 159.0, "the walking jump fell short of the landing (d=%.1f)" % d)
	_check(landed.y > -1.0, "the adventurer dropped into the last hole (y=%.1f)" % landed.y)

	GameManager.touch_mode = false
	Input.action_release("move_forward")
	await _free_hall(hall)


# The input actions the level's on-screen buttons press.
func _touch_actions(level: Node) -> Array[String]:
	var actions: Array[String] = []
	var touch: Node = level.get_node_or_null("TouchControls")
	if touch == null:
		return actions
	for child in touch.get_children():
		if child is TouchScreenButton and child.action != "":
			actions.append(child.action)
	return actions


func test_run_hint_shows_once_per_session() -> void:
	var hall := await _spawn_hall()
	var before: bool = GameManager.run_hint_shown

	# Headless has no screen to draw on, so the overlay is skipped there -
	# what this pins down is the once-per-session bookkeeping.
	GameManager.run_hint_shown = false
	hall._show_run_hint()
	_check(GameManager.run_hint_shown or DisplayServer.get_name() == "headless",
			"the sprint hint did not mark itself as shown")

	# A second visit to Level 2 must not show it again.
	GameManager.run_hint_shown = true
	var layers_before: int = hall.get_children().filter(
			func(n: Node) -> bool: return n is CanvasLayer).size()
	hall._show_run_hint()
	var layers_after: int = hall.get_children().filter(
			func(n: Node) -> bool: return n is CanvasLayer).size()
	_check(layers_after == layers_before, "the sprint hint appeared a second time")

	# The text exists in every language.
	var previous: String = TranslationServer.get_locale()
	TranslationServer.set_locale("de")
	_check(tr("Run with Shift") == "Mit Shift rennen", "the sprint hint is not translated")
	TranslationServer.set_locale(previous)

	GameManager.run_hint_shown = before
	await _free_hall(hall)


func test_touch_options_drop_the_desktop_only_entries() -> void:
	# A phone has one window and one resolution: its screen.
	GameManager.touch_mode = true
	var menu: Control = load("res://ui/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().physics_frame

	var options: Node = menu.get_node("Center/Panel/OptionsItems")
	_check(not options.get_node("DisplayButton").visible,
			"the windowed/fullscreen toggle is offered on a phone")
	_check(not options.get_node("SizeButton").visible,
			"the resolution list is offered on a phone")
	# What is left must still be there.
	for name in ["MusicButton", "LanguageButton", "SoundSlider", "MusicSlider", "BackButton"]:
		_check(options.get_node(name).visible, "%s vanished from the phone options" % name)
	# ...and the music button no longer names a keyboard key.
	_check(not options.get_node("MusicButton").text.contains("(M)"),
			"the phone music button still names the M key")

	GameManager.touch_mode = false
	menu.queue_free()
	await get_tree().physics_frame


func test_touch_mode_croc_hops() -> void:
	GameManager.touch_mode = true
	# The Level-1 rig lives in this scene too, and in touch mode its
	# auto-run holds move_forward down - which would walk the crocodile
	# player around. Only ever one level runs in the real game.
	level.set_physics_process(false)
	Input.action_release("move_forward")

	var crocs := await _spawn_crocs()
	var crocs_player: CharacterBody3D = crocs.get_node("Player")

	# Four hop buttons, one per direction, as a cross centered on the right
	# half of the screen.
	_check(crocs._hop_buttons.size() == 4, "level 6 has %d hop buttons, want 4"
			% crocs._hop_buttons.size())
	var screen_middle: float = get_viewport().get_visible_rect().size.y / 2.0
	var cross_middle := 0.0
	for entry in crocs._hop_buttons:
		var hop_button: TouchScreenButton = entry["node"]
		var diameter: float = hop_button.texture_normal.width
		_check(diameter > 120.0, "the hop buttons are only %.0f px across" % diameter)
		cross_middle += (hop_button.position.y + diameter / 2.0) / 4.0
	_check(absf(cross_middle - screen_middle) < 2.0,
			"the hop cross sits at %.0f px, not centered on %.0f"
			% [cross_middle, screen_middle])

	# Freeze the crocs surfaced and stand on the first one.
	for croc in get_tree().get_nodes_in_group("crocodiles"):
		croc.frozen = true
	var first: Vector3 = crocs._croc_positions[0]
	crocs_player.global_position = crocs.to_global(first + Vector3(0, 1.6, 0))
	for i in 60:
		await get_tree().physics_frame
		if crocs_player.is_on_floor():
			break
	_check(crocs_player.is_on_floor(), "the player never landed on the first croc")
	var z_before: float = crocs.to_local(crocs_player.global_position).z

	# A forward hop must carry him onto a croc further down the river -
	# dry, not swimming. Goes through the button's press signal: a quick
	# tap begins and ends between physics frames, so polling would miss it.
	crocs._on_hop_pressed(Vector3(0, 0, -1))
	await get_tree().physics_frame
	_check(crocs._hopping, "a tapped hop button did not start a hop")
	_check(crocs_player.external_motion, "the hop did not take over the velocity")
	for i in 120:
		await get_tree().physics_frame
		if not crocs._hopping:
			break
	var landed: Vector3 = crocs.to_local(crocs_player.global_position)
	_check(not crocs_player.is_dying(), "the forward hop drowned the player")
	_check(landed.z < z_before - 1.0,
			"the hop did not carry him downriver (z %.2f -> %.2f)" % [z_before, landed.z])
	_check(not crocs_player.external_motion,
			"the level still owns the velocity after landing")

	# The crossing is watched from the side, not from dead astern: seen down
	# their own spines the crocs hide their eyes behind their backs, and the
	# eyes going red are the only warning before a back sinks.
	_check(absf(crocs_player.camera_pivot.rotation.y) > deg_to_rad(10.0),
			"the phone camera sits straight behind the adventurer (yaw %.0f deg)"
			% rad_to_deg(crocs_player.camera_pivot.rotation.y))
	# Drowning resets the player's camera; the angle has to come back with it.
	crocs_player.reset_to_start(crocs._spawn_transform)
	await get_tree().physics_frame
	_check(absf(crocs_player.camera_pivot.rotation.y) > deg_to_rad(10.0),
			"the camera angle was lost on the respawn")

	GameManager.touch_mode = false
	level.set_physics_process(true)
	crocs.queue_free()
	await get_tree().physics_frame


# A croc that is still under water when the button is tapped, but breaks
# the surface while the player is in the air, is a landing spot: aiming
# past it turned the hop into a blind leap into the river.
func test_touch_hop_aims_at_a_croc_surfacing_mid_flight() -> void:
	GameManager.touch_mode = true
	var crocs := await _spawn_crocs()
	crocs.set_physics_process(false)   # no drowning while we place the player

	# Leave a single croc to aim at, and dunk it: under water now, back up
	# in about a second - mid-hop.
	var target_croc: Node3D = null
	for croc in get_tree().get_nodes_in_group("crocodiles"):
		if not crocs.is_ancestor_of(croc):
			continue
		if target_croc == null:
			target_croc = croc
		else:
			croc.remove_from_group("crocodiles")
	_check(target_croc != null, "the river has no crocodiles")
	var air_time: float = crocs._hop_air_time()
	target_croc._time = target_croc.cycle_length() - 0.9
	await get_tree().physics_frame
	_check(target_croc.position.y < target_croc.surface_y - crocs.CROC_SUNK_MARGIN,
			"the test croc is not under water")
	_check(target_croc.height_in(air_time) > target_croc.surface_y - crocs.CROC_SUNK_MARGIN,
			"the test croc has not surfaced again by the end of a hop")

	var from: Vector3 = target_croc.global_position + Vector3(0.0, 1.0, 4.5)
	var target: Vector3 = crocs._hop_target(Vector3(0, 0, -1), from, air_time)
	var missed := Vector2(target.x - target_croc.global_position.x,
			target.z - target_croc.global_position.z).length()
	_check(missed < 0.5,
			"the hop ignored a croc surfacing mid-flight (aimed %.1f m off it)" % missed)

	GameManager.touch_mode = false
	crocs.queue_free()
	await get_tree().physics_frame


func test_touch_mode_slide_buttons() -> void:
	GameManager.touch_mode = true
	var slide := await _spawn_slide()
	var touch: Node = slide.get_node_or_null("TouchControls")
	_check(touch != null, "slide touch controls missing")
	var actions: Array[String] = []
	if touch:
		for child in touch.get_children():
			if child is TouchScreenButton and child.action != "":
				actions.append(child.action)
	for action in ["move_left", "move_right", "jump"]:
		_check(actions.has(action), "slide button for %s missing" % action)
	_check(not slide.get_node("ControlsHint").visible,
			"keyboard hints still visible on the touch slide")

	# The phone ride spaces its blocks out - and rides further to make up
	# for it: a longer chute, with the cavern and the exit zone following
	# it down.
	var blocks: Array = slide._obstacles()
	for i in range(1, blocks.size()):
		var gap: float = absf(blocks[i].y - blocks[i - 1].y)
		_check(gap >= slide.MIN_OBSTACLE_GAP_TOUCH - 0.01,
				"only %.1f m between touch blocks %d and %d" % [gap, i - 1, i])
	_check(slide._end_z() < slide.SLIDE_END_Z - 60.0,
			"the touch chute is not longer than the desktop one (%.0f)" % slide._end_z())
	_check(slide._holes().size() > slide.HOLES.size(),
			"the longer touch chute got no extra holes")
	for hole in slide._holes():
		_check(hole > slide._end_z() + 6.0, "a hole sits at the very end of the chute")
	for block in blocks:
		_check(block.y > slide._end_z() + 4.0, "a block sits past the end of the chute")
	var slide_end: Area3D = slide.get_node("EndZone")
	var end_local: Vector3 = slide.to_local(slide_end.global_position)
	_check(end_local.z < slide._end_z(), "the touch exit zone stayed at the old chute end")
	_check(end_local.y < slide._end_y() - 4.0, "the touch exit zone is not down in the water")

	# And the new stretch is real chute: set down in it (past the desktop's
	# end, between a hole and a block), he keeps riding instead of dropping
	# through the world.
	var far_z := -164.0
	var rider: CharacterBody3D = slide.get_node("Player")
	rider.global_position = slide.to_global(Vector3(1.5, slide._ramp_y(far_z) + 1.0, far_z))
	slide._sliding = true
	for i in 30:
		await get_tree().physics_frame
	var late: Vector3 = slide.to_local(rider.global_position)
	_check(late.z < far_z, "the ride stalled in the extended chute")
	_check(late.y > slide._ramp_y(late.z) - 1.5,
			"no floor under the extended chute at z=%.0f (y %.1f, chute %.1f)"
			% [late.z, late.y, slide._ramp_y(late.z)])
	_check(not rider.is_dying(), "the extended chute killed the rider on its own")

	# ... and it is watched from higher up, looking down the slope, with
	# ceiling enough that the camera arm never hits it.
	var slide_player: CharacterBody3D = slide.get_node("Player")
	var arm: SpringArm3D = slide_player.get_node("CameraPivot/CameraArm")
	_check(slide_player.camera_pivot.rotation.x < deg_to_rad(-15.0),
			"the touch slide camera does not look down the chute")
	_check(arm.spring_length > 3.5, "the touch slide camera did not pull back")
	_check(slide._wall_height() > slide.WALL_HEIGHT,
			"the touch chute has no extra headroom for the raised camera")

	GameManager.touch_mode = false
	slide.queue_free()
	await get_tree().physics_frame


func test_translation_csv_complete() -> void:
	var file := FileAccess.open("res://localization/strings.csv", FileAccess.READ)
	_check(file != null, "localization/strings.csv missing")
	if file == null:
		return

	var header := file.get_csv_line()
	var expected := PackedStringArray(["keys"])
	for entry in GameManager.LANGUAGES:
		expected.append(entry[0])
	_check(header == expected, "CSV columns do not match GameManager.LANGUAGES")

	var rows := 0
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() == 1 and row[0].is_empty():
			continue
		rows += 1
		_check(row.size() == header.size(),
				"row '%s' has %d of %d cells" % [row[0], row.size(), header.size()])
		for i in mini(row.size(), header.size()):
			_check(not row[i].strip_edges().is_empty(),
					"empty %s cell in row '%s'" % [header[i], row[0]])
	_check(rows >= 50, "unexpectedly few translation rows: %d" % rows)


func test_language_switch_and_persistence() -> void:
	var prev_language: String = GameManager.language
	var prev_config := ConfigFile.new()
	prev_config.load(GameManager.SETTINGS_PATH)
	var had_key: bool = prev_config.has_section_key("general", "language")

	GameManager.set_language("de")
	_check(TranslationServer.get_locale().begins_with("de"), "locale did not switch to de")
	_check(tr("Resume") == "Fortsetzen", "German translation missing for 'Resume'")
	var saved := ConfigFile.new()
	saved.load(GameManager.SETTINGS_PATH)
	_check(str(saved.get_value("general", "language", "")) == "de", "language not persisted")

	GameManager.set_language("ja")
	_check(tr("Options") == "オプション", "Japanese translation missing for 'Options'")
	_check(tr("GOD MODE") == "GOD MODE", "untranslated strings must fall through unchanged")

	# Restore the player's language and, on a first-launch settings file
	# (no language key yet), the pristine auto-detect state.
	GameManager.set_language(prev_language)
	if not had_key:
		var cleanup := ConfigFile.new()
		cleanup.load(GameManager.SETTINGS_PATH)
		cleanup.erase_section_key("general", "language")
		cleanup.save(GameManager.SETTINGS_PATH)


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
	_check(stairs._spawn_interval(0.0) > stairs._spawn_interval(1.0) + 0.5,
			"boulder interval does not ramp up the stairs")

	var stairs_player: CharacterBody3D = stairs.get_node("Player")
	_check(stairs._progress() < 0.05, "progress not zero at the bottom")
	stairs_player.global_position = stairs.to_global(
			Vector3(0, stairs._ramp_y(-57.0) + 1.0, -57.0))
	_check(absf(stairs._progress() - 0.5) < 0.05, "progress wrong mid-climb")

	# The final stretch stays clear: no fresh boulders near the top.
	stairs_player.global_position = stairs.to_global(
			Vector3(0, stairs._ramp_y(-108.0) + 1.0, -108.0))
	var before := get_tree().get_nodes_in_group("boulders").size()
	stairs._on_boulder_timer_timeout()
	_check(get_tree().get_nodes_in_group("boulders").size() == before,
			"a boulder spawned in the calm final stretch")
	stairs._boulder_timer.stop()

	# Boulders spawn a stretch above the player, not at the distant top.
	stairs_player.global_position = stairs.to_global(Vector3(0, 1.0, 3.0))
	var near: Node3D = stairs._spawn_boulder()
	_check(near.position.z > -50.0,
			"boulder spawned too far up the stairs: z=%f" % near.position.z)

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
	var chamber_player: CharacterBody3D = chamber.get_node("Player")
	# Into the chamber's entry strip — NOT onto the pit strip, or the
	# player rides the trapdoor straight into the end zone and the scene
	# change kills the test run. (In play the door is open before the
	# dials are reachable; this test never lights the bowls.)
	chamber_player.global_position = chamber.to_global(Vector3(3.0, 0.5, -9.2))

	# Every drum carries four symbols (plus the drum mesh, gold rims and
	# the scarab), so each turn brings a different glyph to the front.
	_check(chamber._dials[0]._drum.get_child_count() >= 5,
			"dial drum does not carry four symbols")

	# One turn each is not enough: each wheel must complete TWO turns
	# to bring the target symbol to the front.
	for dial in chamber._dials:
		dial.interact()
	for i in 60:
		await get_tree().physics_frame
	_check(not chamber.floor_open, "floor opened before the wheels reached their position")

	for dial in chamber._dials:
		_check(not chamber.floor_open, "floor opened before all dials were solved")
		dial.interact()
		await get_tree().physics_frame

	for i in 150:
		await get_tree().physics_frame
	_check(chamber.floor_open, "all dials turned but the floor stayed shut")
	# The wheels keep turning forever, even after they are solved.
	_check(chamber._dials[0].can_interact(),
			"a solved dial refused further turns")
	# Turning grinds, and the opening pit spawned its rumble player (the
	# 1.8 s sound itself has already finished by now).
	_check(chamber._dials[0]._turn_player.stream != null, "dial has no turn sound")
	var rumble_found := false
	for child in chamber.get_children():
		if child is AudioStreamPlayer and child.stream == chamber.RUMBLE_SOUND:
			rumble_found = true
	_check(rumble_found, "the opening pit made no rumble")
	_check(chamber._pit_slabs[0].position.y < -8.0, "pit trapdoor did not drop away")
	for dial in chamber._dials:
		_check(dial.position.y < -5.0, "dial socket did not fall into the pit")
	# Whoever still stands beside the pit is dragged in: the antechamber
	# test player is being pulled toward the pit right now, stunned, and
	# the dial blockers are gone (fallen into the pit they were invisible
	# platforms that caught the player above the end zone).
	_check(chamber._pulling, "the player is not being pulled into the pit")
	_check(not chamber_player.is_physics_processing(),
			"the player is not stunned during the pull")
	for blocker in chamber._dial_blockers:
		_check(not is_instance_valid(blocker), "a dial blocker survived into the pit")
	# The pull must carry the player past the old y=-2 freeze point.
	var lowest := 0.0
	for i in 210:
		await get_tree().physics_frame
		lowest = minf(lowest, chamber.to_local(chamber_player.global_position).y)
		if lowest < -5.0:
			break
	_check(lowest < -5.0, "the player froze mid-air instead of falling: y=%f" % lowest)

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
	_check(slide._bump_player.playing, "hitting the block made no bump sound")
	_check(not slide_player._hit_player.playing,
			"the spear-hit cry played instead of the bump")
	slide.queue_free()
	await get_tree().physics_frame


func test_slide_jump_stays_low() -> void:
	var slide := await _spawn_slide()
	var slide_player: CharacterBody3D = slide.get_node("Player")
	# Ride onto the chute, then hold jump: the hop over the chute line
	# must stay a hop, not a flight to the ceiling.
	for i in 60:
		await get_tree().physics_frame
	Input.action_press("jump")
	var max_clearance := 0.0
	for i in 120:
		await get_tree().physics_frame
		var lp: Vector3 = slide.to_local(slide_player.global_position)
		if lp.z < -3.0:
			max_clearance = maxf(max_clearance,
					lp.y - 0.9 - slide._ramp_y(lp.z))
	Input.action_release("jump")
	_check(max_clearance < 2.0,
			"slide jump flies too high above the chute: %f" % max_clearance)
	_check(max_clearance > 0.3, "slide jump never left the chute")
	slide.queue_free()
	await get_tree().physics_frame


func test_slide_glide_sound_follows_jumps() -> void:
	var slide := await _spawn_slide()
	var slide_player: CharacterBody3D = slide.get_node("Player")
	for i in 30:
		await get_tree().physics_frame
	_check(slide._glide_player.playing, "glide sound silent while sliding")
	Input.action_press("jump")
	var silent_in_air := false
	for i in 60:
		await get_tree().physics_frame
		if not slide_player.is_on_floor() and not slide._glide_player.playing:
			silent_in_air = true
	Input.action_release("jump")
	_check(silent_in_air, "glide sound kept playing during the jump")
	for i in 60:
		await get_tree().physics_frame
		if slide_player.is_on_floor():
			break
	_check(slide_player.is_on_floor(), "player did not land after the jump")
	_check(slide._glide_player.playing, "glide sound did not resume after landing")
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
	# High enough that the landing is as fast as a real jump's.
	crocs_player.global_position = crocs.to_global(
			crocs._croc_positions[0] + Vector3(0, 2.2, 0))
	var landing_heard := false
	for i in 40:
		await get_tree().physics_frame
		landing_heard = landing_heard or crocs_player._land_player.playing
	_check(not crocs_player.is_dying(), "standing on a surfaced croc killed the player")
	_check(crocs_player.is_on_floor(), "player does not stand on the croc's back")
	_check(landing_heard, "landing on the croc made no sound")
	crocs.queue_free()
	await get_tree().physics_frame


# In god mode the river carries the player: an invisible walkway lets
# them stroll over the water to the jetty.
func test_croc_god_mode_walks_on_water() -> void:
	var crocs := await _spawn_crocs()
	var crocs_player: CharacterBody3D = crocs.get_node("Player")
	GameManager.god_mode = true
	GameManager.god_mode_changed.emit(true)
	crocs_player.global_position = crocs.to_global(Vector3(4.0, 0.5, -20.0))
	for i in 40:
		await get_tree().physics_frame
	_check(not crocs_player.is_dying(), "god mode player drowned on the water")
	_check(crocs_player.is_on_floor(), "god mode player does not stand on the water")
	GameManager.god_mode = false
	GameManager.god_mode_changed.emit(false)
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
	# Exactly ONE sound: the splash. No whistle, no fall cry, no hit.
	_check(crocs._splash_player.playing, "going under made no splash sound")
	_check(not crocs_player._whistle_player.playing, "fall whistle played on drowning")
	_check(not crocs_player._fall_player.playing, "fall cry played on drowning")
	_check(not crocs_player._hit_player.playing, "hit sound played on drowning")
	crocs.queue_free()
	await get_tree().physics_frame


func test_croc_gaps_widen_along_the_river() -> void:
	var crocs := await _spawn_crocs()
	var positions: Array[Vector3] = crocs._croc_positions
	# The starter raft has pairs sharing a row; compare row distances.
	var rows: Array[float] = []
	for p in positions:
		if rows.is_empty() or absf(p.z - rows.back()) > 0.01:
			rows.append(p.z)
	var first_gap: float = rows[0] - rows[1]
	var last_gap: float = rows[rows.size() - 2] - rows[rows.size() - 1]
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


# The steamer sits in living water: a foam collar, bow rings and a wake,
# riding at the waterline and animating as the boat steams down the Nile.
func test_credits_boat_has_animated_water() -> void:
	var credits: Node3D = load("res://levels/nile_credits.tscn").instantiate()
	credits.position = Vector3(1800.0, 0.0, 0.0)
	add_child(credits)
	await get_tree().process_frame
	_check(credits._water_fx != null, "the credits boat has no water around it")
	_check(credits._ripples.size() >= 4,
			"too few water elements: %d" % credits._ripples.size())
	_check(is_equal_approx(credits._water_fx.position.y, credits.WATER_Y),
			"the foam does not sit at the waterline")

	# A bow ring is one of the swelling, fading rings (not the collar or wake).
	var ring: Dictionary = {}
	for r in credits._ripples:
		if not r.get("collar", false) and not r.get("wake", false):
			ring = r
			break
	_check(not ring.is_empty(), "no bow ripple ring among the water elements")
	var phase_before: float = ring.get("phase", -1.0)
	for i in 20:
		await get_tree().process_frame
	_check(not is_equal_approx(ring["phase"], phase_before),
			"the bow ripples do not animate")
	# The foam tracks the boat down the river rather than sitting still.
	_check(is_equal_approx(credits._water_fx.position.z, credits._boat.position.z),
			"the water did not follow the boat downriver")

	credits.queue_free()
	await get_tree().physics_frame


# Past the end of one pass the scroll wraps around and keeps rolling
# instead of leaving the level (only ESC or the end of the music do).
func test_credits_scroll_loops_endlessly() -> void:
	var credits: Node3D = load("res://levels/nile_credits.tscn").instantiate()
	credits.position = Vector3(1800.0, 0.0, 0.0)
	add_child(credits)
	await get_tree().process_frame
	credits._time = credits.SCROLL_TIME + 0.2
	await get_tree().process_frame
	_check(credits._scroll.position.y > 0.0,
			"credits scroll did not wrap around after a full pass")
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
