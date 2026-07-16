class_name CombineRecipe
extends Resource

## The [CombinableItem.id] of the item that must be combined into the base item.
@export var ingredient_id: StringName

## The scene the base item turns into when [member ingredient_id] is combined in.
@export var result: PackedScene
