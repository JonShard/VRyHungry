extends Panel

@export var station_scene: PackedScene
@export var icon_texture: Texture2D
@export var station_name: String = "Station"
@export var cost: int = 100

@export var name_label: Label
@export var cost_label: Label
@export var button: Button


func _ready() -> void:
	name_label.text = station_name
	cost_label.text = str(cost) + "$"
	button.icon = icon_texture


func _on_button_pressed() -> void:
	print("ShopStationButton buy ", station_name)
	_buy_station()
	
	
func _buy_station() -> void:
	print("ShopStationButton _buy_station:, ", "cost=", cost, " current money=", GameManager.money)
	GameManager.set_money(GameManager.money - cost)
	var transform = Helper.get_snapped_transform(XRHelpers.get_xr_origin(self).get_node_or_null("PlayerBody"))
	var forward: Vector3 = -transform.basis.z.normalized()
	transform.origin += (forward * 0.6)
	var instance = NetworkManager.spawn_item(station_scene.resource_path, transform)

	if NetworkManager.is_online() and not NetworkManager.is_server():
		_ask_server_to_spawn.rpc_id(1, station_scene.resource_path, transform)

	Signals.station_bought.emit(instance)
	
@rpc("any_peer", "call_remote", "reliable")
func _ask_server_to_spawn(station_scene_path, transform):
	NetworkManager.spawn_item(station_scene_path, transform)

func _process(_delta: float) -> void:
	button.disabled = GameManager.money < cost
	
