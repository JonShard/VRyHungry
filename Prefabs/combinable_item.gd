class_name CombinableItem
extends Node

## Identity of this item, referenced by other items' recipes.
@export var id: StringName

## Recipes describing what the item holding this component turns into when
## another item is combined into it while snapped. Recipes are directional:
## only the snapped (base) item's recipes are consulted.
@export var recipes: Array[CombineRecipe] = []


func _ready() -> void:
	if id.is_empty():
		push_error("CombinableItem on ", get_parent().name, " has no 'id' set.")


## Returns the scene this item becomes when combined with [param other_id],
## or null if there is no matching recipe.
func get_result_for(other_id: StringName) -> PackedScene:
	for recipe in recipes:
		if recipe and recipe.ingredient_id == other_id:
			return recipe.result
	return null
