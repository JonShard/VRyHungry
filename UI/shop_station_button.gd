extends Panel

@export var station_scene: PackedScene
@export var icon_texture: Texture2D
@export var station_name: String = "Station"
@export var cost: int = 100

@export var name_label: Label
@export var cost_label: Label
@export var button: Button


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	name_label.text = station_name
	cost_label.text = str(cost) + "$"
	button.icon = icon_texture


func _on_button_pressed() -> void:
	print("ShopStationButton buy ", station_name)
