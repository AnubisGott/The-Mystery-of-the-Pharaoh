extends Node3D

# A boulder rolling down the Level-3 staircase in a fixed lane. It moves
# in the level's local space along the slope line (the level aims it),
# flattens out on the bottom platform and despawns behind the player.
signal player_hit

const RADIUS: float = 0.75

var speed: float = 7.0
var direction: Vector3 = Vector3.ZERO   # unit vector, downhill, level-local
var flatten_z: float = 1000000.0        # roll horizontally past this z
var despawn_z: float = 1000000.0        # free itself past this z

var _mesh: MeshInstance3D


func _ready() -> void:
	add_to_group("boulders")

	# UV-mapped sand texture (not triplanar), so the rolling is visible.
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.62, 0.52, 0.4)
	material.albedo_texture = load("res://textures/aerial_sand_diff_1k.jpg")
	material.roughness = 0.95

	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	sphere.material = material
	_mesh = MeshInstance3D.new()
	_mesh.mesh = sphere
	add_child(_mesh)

	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var ball := SphereShape3D.new()
	ball.radius = RADIUS * 0.9
	shape.shape = ball
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if position.z > flatten_z and direction.y != 0.0:
		direction = Vector3(0, 0, 1)
	position += direction * speed * delta
	# Roll around the lateral axis at matching surface speed.
	_mesh.rotate_x(speed * delta / RADIUS)
	if position.z > despawn_z:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_hit.emit()
