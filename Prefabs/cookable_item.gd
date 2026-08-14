class_name CookableItem
extends Node

@export_range(0.0, 30.0, 0.5, "or_greater", "suffix:s") var cooking_time: float = 4.0
@export var turns_into: PackedScene

func _ready() -> void:
	if not turns_into:
		SweetLogger.warning("{0} missing turns_into reference", [name])
