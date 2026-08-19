class_name FoodItem
extends Node

# Define the Enum at the top of your script
enum Type { MEAL, SIDE, INGREDIENT, NONE }

@export var enabled: bool = true

@export var id: String
@export var type: Type = Type.NONE
@export var sell_value = 1
var is_absorbed = false # Used by tables to keep track of whether the item has been registered as delivered already
