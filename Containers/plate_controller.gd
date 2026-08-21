class_name PlateController
extends Node

@export var net_pickable: NetPickable
@export var dirty_node: Node3D
@export var container: ItemContainer


## Synced summary of the plate's contents (item ids). The contents themselves
## are the real item nodes ItemContainer reparents under the plate; this is only
## what other systems read to ask "what is on this plate" without walking them.
@export var contained_ids: Array[String] = []
@export var enabled = true:
	get:
		return enabled
	set(value):
		if NetworkManager.owns_world():
			clients_set_enabled.rpc(value)
		enabled = value
		container.enabled = not is_dirty
		net_pickable.grabbable = value
		SweetLogger.info("Set plate enabled: {0}", [value])

@rpc("authority", "call_remote", "reliable")
func clients_set_enabled(value: bool) -> void:
	enabled = value

	
@export var is_dirty: bool = false:
	get:
		return is_dirty
	set(value):
		if NetworkManager.owns_world():
			clients_set_dirty.rpc(value)
		is_dirty = value
		container.enabled = not value
		dirty_node.visible = value
		SweetLogger.info("Set plate dirty: {0}", [value])

@rpc("authority", "call_remote", "reliable")
func clients_set_dirty(value: bool) -> void:
	is_dirty = value


func get_food_items() -> Array[FoodItem]:
	return container.contained_items

func _ready() -> void:
	Helper.check_reference(self, dirty_node, Node3D)
	Helper.check_reference(self, net_pickable, NetPickable)
	Helper.check_reference(self, container, ItemContainer)