class_name PlateController
extends Node

@onready var dirty_node: Node3D = $"../Dirty"
@onready var container: ItemContainer = $"../Container"

@export var is_dirty: bool = false

## Synced summary of the plate's contents (item ids). The contents themselves
## are the real item nodes ItemContainer reparents under the plate; this is only
## what other systems read to ask "what is on this plate" without walking them.
@export var contained_ids: Array[String] = []

func get_food_items() -> Array[FoodItem]:
	return container.contained_items

func _ready() -> void:
	if not dirty_node:
		SweetLogger.warning("{0} missing dirty_node reference", [name])
	dirty_node.visible = is_dirty


func _process(_delta: float) -> void:
	if is_dirty:
		container.enabled = false
		dirty_node.visible = true
	else:
		container.enabled = true
		dirty_node.visible = false
