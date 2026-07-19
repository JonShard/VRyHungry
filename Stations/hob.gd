extends StaticBody3D

const RECIPE_MANAGER = preload("res://RecipeManager.gd")

@export var cook_speed = 1
@onready var snap_zone: XRToolsSnapZone = $XRToolsSnapZone

var time_cooked = 0
var cooking_result = null
var cooking_result_time = 0 

func _ready() -> void:
	snap_zone.has_picked_up.connect(_on_object_picked_up)
	snap_zone.has_dropped.connect(_on_object_dropped)

func _on_object_picked_up(_item) -> void:
	print("Hob: object picked up: ", _item)

	# Find the CookableItem in held object
	var _food_item = _item.get_node_or_null("FoodItem") as FoodItem
	if not _food_item:
		print("Hob: held object is not a FoodItem")
		return
	var result = RECIPE_MANAGER.get_cooking_result(_food_item.id)
	if not result:
		print("Hob: held a FoodItem that is not cookable, id: ", _food_item.id)
		return

	cooking_result = result
	cooking_result_time = RECIPE_MANAGER.get_cooking_time(_food_item.id) 


func _on_object_dropped() -> void:
	print("Hob: object drop ")
	time_cooked = 0
	cooking_result = null
	cooking_result_time = 0 


func convert_held_to_item(_item: PackedScene) -> void:
	print("Hob converting ", _item)
	
	var old_pickable = snap_zone.picked_up_object
	if not old_pickable:
		push_warning("Hob finished cooking _item, but snap zone is missing its reference")
		return
	
	# Create new item as child of root in the same position
	var original_transform = old_pickable.global_transform
	var new_scene_instance = _item.instantiate()
	get_tree().get_root().add_child(new_scene_instance)
	new_scene_instance.global_transform = original_transform

	# Drop and free the old item and pick up the new one
	print("Hob freeing old_pickable  ", old_pickable)
	snap_zone.drop_object() 
	old_pickable.queue_free()
	snap_zone.pick_up_object(new_scene_instance)
	

# If cooking something, progress cooking, when done, convert item
func _process(delta: float) -> void:	
	if cooking_result:
		time_cooked += cook_speed * delta		
		if time_cooked >= cooking_result_time:
			time_cooked = 0
			convert_held_to_item(cooking_result)
		
