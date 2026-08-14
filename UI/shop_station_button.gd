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


func _process(_delta: float) -> void:
	button.disabled = GameManager.money < cost


func _on_button_pressed() -> void:
	SweetLogger.debug("Buy {0}", [station_name])
	_buy_station()


func _buy_station() -> void:
	SweetLogger.debug("Cost={0} current money={1}", [cost, GameManager.money])
	GameManager.set_money(GameManager.money - cost)
	var transform = Helper.get_snapped_transform(XRHelpers.get_xr_origin(self).get_node_or_null("PlayerBody"))
	var forward: Vector3 = -transform.basis.z.normalized()
	transform.origin += (forward * 0.6)

	var instance
	if NetworkManager.is_online() and not NetworkManager.is_server():
		_ask_server_to_spawn.rpc_id(1, station_scene.resource_path, transform)
	else:
		instance = NetworkManager.spawn_item(station_scene.resource_path, transform)
		update_instance_move(instance)
	Signals.station_bought.emit(instance)


@rpc("any_peer", "call_remote", "reliable")
func _ask_server_to_spawn(station_scene_path, transform):
	if not multiplayer.is_server():
		return
	var instance = NetworkManager.spawn_item(station_scene_path, transform)
	update_instance_move(instance)


func update_instance_move(instance: Node3D) -> void:
	var move = Helper.find_first_child_of_type(instance, StationMovement) as StationMovement
	if not move:
		SweetLogger.error("Could not find StationMovement under station {0}", [instance.name])
	move.server_artificial_pickup() # Make the new station appear as ghost, the player has to place it.


	
