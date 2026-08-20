class_name CookableItem
extends Node

@export_range(0.0, 30.0, 0.5, "or_greater", "suffix:s") var cooking_time: float = 4.0
@export var turns_into: PackedScene

func _ready() -> void:
	Helper.check_reference(self, turns_into, PackedScene)
