extends Node3D

# Level 7: the journey home. The adventurer sits on the Nile steamboat
# while the credits roll over the scene in an endless loop. The level
# ends when the music finishes or on ESC.

const LEVEL_MUSIC: AudioStream = preload("res://soundAndMusic/music/AztekenherausforderungLevel07.mp3")
const CHARACTER: PackedScene = preload("res://models/adventurer_realistic.glb")

const SCROLL_TIME: float = 38.0
const CREDITS: Array[Array] = [
	["The Mystery of the Pharaoh", 52],
	["", 20],
	["A game by", 22],
	["Anubis", 34],
	["", 30],
	["Creative Director", 22],
	["Anubis", 30],
	["", 20],
	["Level Design", 22],
	["Claude Code", 30],
	["", 20],
	["Programming", 22],
	["Claude Code", 30],
	["", 20],
	["Testing", 22],
	["Anubis & Friends", 30],
	["", 30],
	["Music", 22],
	["Suno", 30],
	["", 20],
	["Sound Effects", 22],
	["freesound.org & Claude Code", 30],
	["", 20],
	["Artwork", 22],
	["Nano Banana", 30],
	["", 30],
	["Game Engine", 22],
	["Godot", 30],
	["", 30],
	["Character", 22],
	["MakeHuman / MPFB2 (MakeHuman community)", 24],
	["Clothes by namuhekam, cortu, culturalibre (CC0)", 24],
	["", 20],
	["Animations", 22],
	["Universal Animation Library by Quaternius (CC0)", 24],
	["", 20],
	["Sphinx head scan", 22],
	["\"The Great Sphinx of Giza\" by Chenzoss (CC-BY 4.0)", 24],
	["", 20],
	["Textures", 22],
	["Poly Haven (CC0)", 24],
	["", 40],
	["Thank you for playing!", 36],
]

var _boat: Node3D
var _scroll: VBoxContainer
var _time: float = 0.0
var _view_height: float = 648.0


func _ready() -> void:
	# The track plays once, not looped: its end is what ends the level.
	GameManager.play_music(LEVEL_MUSIC, false)
	GameManager.music_finished.connect(_on_music_finished)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_scene()
	_build_credits()


func _process(delta: float) -> void:
	_time += delta
	# The boat steams down the Nile riding a gentle swell; the camera is
	# aboard, so the banks and palms drift past.
	_boat.position.z -= delta * 2.0
	_boat.position.y = 0.1 + 0.08 * sin(_time * 0.7)
	_boat.rotation.z = 0.012 * sin(_time * 0.55 + 1.0)

	# The scroll wraps around endlessly; leaving is the music's (or the
	# ESC key's) job. The height is re-read so window changes mid-roll
	# keep the wrap points on screen.
	_view_height = get_viewport().get_visible_rect().size.y
	var progress := fposmod(_time / SCROLL_TIME, 1.0)
	_scroll.position.y = _view_height - (_view_height + _scroll.size.y + 60.0) * progress


func _on_music_finished() -> void:
	GameManager.show_main_menu()


func _unhandled_input(event: InputEvent) -> void:
	# ESC leaves for the menu — a fresh press only, ignoring key repeats
	# left over from the sprint onto the boat.
	if _time > 1.0 and event is InputEventKey and event.is_pressed() \
			and not event.is_echo() and event.physical_keycode == KEY_ESCAPE:
		GameManager.show_main_menu()


func _build_scene() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.25, 0.4, 0.68)
	sky_material.sky_horizon_color = Color(0.95, 0.72, 0.5)
	sky_material.ground_bottom_color = Color(0.7, 0.6, 0.4)
	sky_material.ground_horizon_color = Color(0.95, 0.72, 0.5)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.9, 0.75, 0.55)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1, 0.8, 0.55)
	sun.light_energy = 1.2
	sun.rotation_degrees = Vector3(-20, 140, 0)
	sun.shadow_enabled = true
	add_child(sun)

	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.14, 0.32, 0.4, 0.9)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.08
	water.metallic = 0.4
	var river := MeshInstance3D.new()
	var river_mesh := BoxMesh.new()
	river_mesh.size = Vector3(300, 0.4, 300)
	river_mesh.material = water
	river.mesh = river_mesh
	river.position = Vector3(0, -0.5, 0)
	add_child(river)

	# Banks with palms along the journey ahead.
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color(0.8, 0.68, 0.48)
	for data: Array in [[47.0, 20.0], [-40.0, -15.0], [45.0, -45.0],
			[-38.0, -80.0], [50.0, -115.0], [-42.0, -150.0]]:
		var bank := MeshInstance3D.new()
		var bank_mesh := SphereMesh.new()
		bank_mesh.radius = 22.0
		bank_mesh.height = 6.0
		bank_mesh.material = sand
		bank.mesh = bank_mesh
		bank.position = Vector3(data[0], -1.5, data[1])
		add_child(bank)
		for i in 3:
			var palm := NileProps.build_palm(4.4 + 0.7 * i)
			palm.position = Vector3(data[0] + i * 4.0 - 4.0, 0.6, data[1] + (i - 1) * 5.0)
			palm.rotation.y = i * 2.1 + data[1]
			add_child(palm)

	_boat = NileProps.build_boat()
	add_child(_boat)

	# The adventurer lounges in a deck chair on the foredeck, sunglasses
	# on, angled toward the camera.
	var chair := _build_lounge_chair()
	chair.position = Vector3(0, 1.05, -4.2)
	chair.rotation.y = 2.5
	_boat.add_child(chair)
	var character: Node3D = CHARACTER.instantiate()
	character.position = Vector3(0, 0.08, 0.32)
	character.rotation.x = -0.45   # reclined against the backrest
	chair.add_child(character)
	var anim: AnimationPlayer = character.get_node("AnimationPlayer")
	anim.get_animation("Crouch_Idle").loop_mode = Animation.LOOP_LINEAR
	anim.play("Crouch_Idle")
	_add_sunglasses(character)

	# Smoke from the funnel.
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	var smoke_material := StandardMaterial3D.new()
	smoke_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smoke_material.vertex_color_use_as_albedo = true
	quad.material = smoke_material
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 0.4))
	fade.add_point(Vector2(1.0, 1.0))
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.3, 0.3, 0.3, 0.6))
	ramp.set_color(1, Color(0.6, 0.6, 0.6, 0.0))
	var smoke := CPUParticles3D.new()
	smoke.mesh = quad
	smoke.amount = 24
	smoke.lifetime = 3.5
	smoke.direction = Vector3(0.3, 1, 0)
	smoke.spread = 10.0
	smoke.gravity = Vector3.ZERO
	smoke.initial_velocity_min = 0.8
	smoke.initial_velocity_max = 1.4
	smoke.scale_amount_min = 0.6
	smoke.scale_amount_max = 1.0
	smoke.scale_amount_curve = fade
	smoke.color_ramp = ramp
	smoke.position = Vector3(0, 6.4, -0.8)
	_boat.add_child(smoke)

	# The camera rides on the boat, so the shot stays framed while the
	# world drifts by.
	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.position = Vector3(8.0, 3.0, -9.5)
	_boat.add_child(cam)
	cam.look_at(_boat.to_global(Vector3(0, 2.0, -1.5)), Vector3.UP)
	cam.current = true


# A wooden deck chair with striped canvas, facing local +Z.
func _build_lounge_chair() -> Node3D:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.5, 0.36, 0.2)
	wood.roughness = 0.9
	var canvas_a := StandardMaterial3D.new()
	canvas_a.albedo_color = Color(0.85, 0.3, 0.2)
	canvas_a.roughness = 0.95
	var canvas_b := StandardMaterial3D.new()
	canvas_b.albedo_color = Color(0.92, 0.88, 0.8)
	canvas_b.roughness = 0.95

	var chair := Node3D.new()
	for corner: Vector2 in [Vector2(-0.3, 0.42), Vector2(0.3, 0.42),
			Vector2(-0.3, -0.42), Vector2(0.3, -0.42)]:
		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.07, 0.26, 0.07)
		leg_mesh.material = wood
		leg.mesh = leg_mesh
		leg.position = Vector3(corner.x, 0.13, corner.y)
		chair.add_child(leg)
	# Striped canvas seat.
	for i in 4:
		var slat := MeshInstance3D.new()
		var slat_mesh := BoxMesh.new()
		slat_mesh.size = Vector3(0.66, 0.05, 0.24)
		slat_mesh.material = canvas_a if i % 2 == 0 else canvas_b
		slat.mesh = slat_mesh
		slat.position = Vector3(0, 0.28, 0.38 - i * 0.24)
		chair.add_child(slat)
	# The tilted backrest, striped the same way.
	for i in 4:
		var slat := MeshInstance3D.new()
		var slat_mesh := BoxMesh.new()
		slat_mesh.size = Vector3(0.66, 0.24, 0.05)
		slat_mesh.material = canvas_a if i % 2 == 0 else canvas_b
		slat.mesh = slat_mesh
		slat.position = Vector3(0, 0.36 + i * 0.215, -0.52 - i * 0.115)
		slat.rotation.x = -0.5
		chair.add_child(slat)
	return chair


# Black shades, attached to the head bone so they ride the idle sway.
func _add_sunglasses(character: Node3D) -> void:
	var skeleton: Skeleton3D = character.find_child("Skeleton3D", true, false)
	var attach := BoneAttachment3D.new()
	attach.bone_name = "head"
	skeleton.add_child(attach)

	var shade := StandardMaterial3D.new()
	shade.albedo_color = Color(0.03, 0.03, 0.04)
	shade.roughness = 0.2
	shade.metallic = 0.4
	var glasses := Node3D.new()
	attach.add_child(glasses)
	glasses.position = Vector3(0, 0.035, 0.125)
	for data: Array in [[-0.055, 0.075], [0.055, 0.075]]:
		var lens := MeshInstance3D.new()
		var lens_mesh := BoxMesh.new()
		lens_mesh.size = Vector3(data[1], 0.055, 0.02)
		lens_mesh.material = shade
		lens.mesh = lens_mesh
		lens.position = Vector3(data[0], 0, 0)
		glasses.add_child(lens)
	var bridge := MeshInstance3D.new()
	var bridge_mesh := BoxMesh.new()
	bridge_mesh.size = Vector3(0.035, 0.015, 0.018)
	bridge_mesh.material = shade
	bridge.mesh = bridge_mesh
	glasses.add_child(bridge)
	for side: float in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(0.015, 0.015, 0.13)
		arm_mesh.material = shade
		arm.mesh = arm_mesh
		arm.position = Vector3(side * 0.095, 0, -0.06)
		glasses.add_child(arm)


func _build_credits() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	_scroll = VBoxContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_theme_constant_override("separation", 10)
	root.add_child(_scroll)

	# The exit hint, right-aligned like the level control hints.
	var hint := Label.new()
	hint.text = "Esc - Main Menu"
	hint.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	hint.offset_left = -300.0
	hint.offset_right = -24.0
	hint.offset_top = -12.0
	hint.offset_bottom = 12.0
	hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	hint.add_theme_constant_override("shadow_offset_x", 2)
	hint.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(hint)

	for entry: Array in CREDITS:
		var label := Label.new()
		label.text = entry[0]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", entry[1])
		label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
		label.add_theme_constant_override("shadow_offset_x", 3)
		label.add_theme_constant_override("shadow_offset_y", 4)
		_scroll.add_child(label)

	_view_height = get_viewport().get_visible_rect().size.y
	_scroll.position.y = _view_height
