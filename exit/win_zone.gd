extends Area3D

# A level that wants its own finale (a cutscene before the next level
# loads) sets custom_finale and listens for player_entered; by default
# entering the zone completes the level on the spot.
signal player_entered

@export var custom_finale: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		if custom_finale:
			player_entered.emit()
		else:
			GameManager.complete_level()
