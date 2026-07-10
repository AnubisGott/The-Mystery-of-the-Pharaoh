extends CanvasLayer

@onready var count_label: Label = $Root/CountLabel
@onready var status_label: Label = $Root/StatusLabel


func _ready() -> void:
	GameManager.scarab_count_changed.connect(_on_scarab_count_changed)
	GameManager.all_scarabs_collected.connect(_on_all_scarabs_collected)

	_on_scarab_count_changed(GameManager.collected_scarabs, GameManager.REQUIRED_SCARABS)
	status_label.text = "The tomb gate is open" if GameManager.gate_is_open else ""


func _on_scarab_count_changed(current: int, required: int) -> void:
	count_label.text = "Golden scarabs: %d / %d" % [current, required]


func _on_all_scarabs_collected() -> void:
	status_label.text = "The tomb gate is open"
