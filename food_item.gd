class_name FoodItem
extends Node

# Define the Enum at the top of your script
enum Type { MEAL, SIDE, INGREDIENT }

@export var id: String
@export var type: ItemType = Type.INGREDIENT
