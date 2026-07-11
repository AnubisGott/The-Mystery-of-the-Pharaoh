extends Node3D

# Level 7: the journey home. The adventurer sits on the Nile steamboat
# while the credits roll over the scene. Any key skips; when the scroll
# ends, the game returns to the main menu.

const LEVEL_MUSIC: AudioStream = preload("res://soundAndMusic/music/AztekenherausforderungLevel01.mp3")
const CHARACTER: PackedScene = preload("res://models/adventurer_realistic.glb")

const SCROLL_TIME: float = 38.0
const CREDITS: Array[Array] = [
	["The Mystery of the Pharaoh", 52],
	["", 20],
	["A game by", 22],
	["Stefan Gernhardt", 34],
	["", 20],
	["Design & Programming", 22],
	["Stefan Gernhardt", 30],
	["", 30],
	["Built with the Godot Engine", 26],
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
	GameManager.play_music(LEVEL_MUSIC)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_scene()
	_build_credits()


func _process(delta: float) -> void:
	_time += delta
	# The boat rides a gentle swell; the camera drifts alongside.
	_boat.position.y = 0.1 + 0.08 * sin(_time * 0.7)
	_boat.rotation.z = 0.012 * sin(_time * 0.55 + 1.0)

	var progress := _time / SCROLL_TIME
	_scroll.position.y = _view_height - (_view_height + _scroll.size.y + 60.0) * progress
	if progress >= 1.0:
		GameManager.show_main_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_pressed() and (event is InputEventKey or event is InputEventMouseButton):
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

	# Distant banks with palms.
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color(0.8, 0.68, 0.48)
	for data: Array in [[-40.0, -20.0], [45.0, 10.0], [-38.0, 35.0], [50.0, 60.0]]:
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

	# The adventurer, resting on the foredeck.
	var character: Node3D = CHARACTER.instantiate()
	character.position = Vector3(0, 1.1, -3.4)
	character.rotation.y = PI
	_boat.add_child(character)
	var anim: AnimationPlayer = character.get_node("AnimationPlayer")
	anim.get_animation("Crouch_Idle").loop_mode = Animation.LOOP_LINEAR
	anim.play("Crouch_Idle")

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

	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.position = Vector3(9.5, 3.4, 9.0)
	add_child(cam)
	cam.look_at(Vector3(0, 2.4, 0), Vector3.UP)
	cam.current = true


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
