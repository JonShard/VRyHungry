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
	_buy_station()
	
func _buy_station() -> void:
	GameManager.money -= cost
	var transform = Helper.get_snapped_transform(XRHelpers.get_xr_origin(self).get_node_or_null("PlayerBody"))
	var forward: Vector3 = -transform.basis.z.normalized()
	# TODO: Don't move up. Fix scenes.
	transform.origin += (forward * 0.6) + Vector3(0, 0.5, 0)
	var instance = NetworkManager.spawn_item(station_scene.resource_path, transform)
	Signals.station_bought.emit(instance)
	
func _process(_delta: float) -> void:
	button.disabled = GameManager.money < cost
	
