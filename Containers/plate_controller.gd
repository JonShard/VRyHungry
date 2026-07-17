class_name PlateController
extends Node

@onready var dirty_node: Node3D = $"../Dirty"
@onready var container: ItemContainer = $"../Container"

@export var is_dirty: bool = false

func _ready() -> void:
	if not dirty_node:
		push_error("Plate is missing its dirty_node")
	dirty_node.visible = is_dirty


func _process(delta: float) -> void:
	if is_dirty:
		container.enabled = false
		dirty_node.visible = true
	else:
		container.enabled = true
		dirty_node.visible = false
