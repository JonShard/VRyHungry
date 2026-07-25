class_name FoodItem
extends Node

# Define the Enum at the top of your script
enum Type { MEAL, SIDE, INGREDIENT, NONE }

@export var id: String
@export var type: Type = Type.NONE
@export var sell_value = 1
