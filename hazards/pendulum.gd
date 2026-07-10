extends Node3D

# A swinging pendulum blade. Each pendulum rolls its own random period
# when the level starts and again on every player respawn, so no two
# runs feel identical; within a run every blade stays a readable sine.
signal player_hit

const MIN_PERIOD: float = 2.2
const MAX_PERIOD: float = 4.2
const AMPLITUDE: float = deg_to_rad(55.0)
const ARM_LENGTH: float = 3.4

var phase_offset: float = 0.0
var period: float = 3.2

var _time: float = 0.0
var _arm: Node3D


func randomize_speed() -> void:
	period = randf_range(MIN_PERIOD, MAX_PERIOD)


func _ready() -> void:
	add_to_group("pendulums")
	randomize_speed()
	_arm = Node3D.new()
	add_child(_arm)

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.75, 0.75, 0.78)
	metal.metallic = 0.9
	metal.roughness = 0.3
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.3, 0.2, 0.12)

	_add_mesh(_arm, Vector3(0.14, ARM_LENGTH, 0.14), Vector3(0.0, -ARM_LENGTH / 2.0, 0.0), wood)
	_add_mesh(_arm, Vector3(1.5, 0.8, 0.14), Vector3(0.0, -ARM_LENGTH, 0.0), metal)
	_add_mesh(self, Vector3(0.3, 0.3, 1.0), Vector3.ZERO, wood)

	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 0.8, 0.3)
	shape.shape = box
	area.add_child(shape)
	area.position = Vector3(0.0, -ARM_LENGTH, 0.0)
	_arm.add_child(area)
	area.body_entered.connect(_on_body_entered)


func _add_mesh(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	mesh.mesh = box
	mesh.position = pos
	parent.add_child(mesh)


func _physics_process(delta: float) -> void:
	_time += delta
	_arm.rotation.z = AMPLITUDE * sin(TAU * _time / period + phase_offset)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_hit.emit()
