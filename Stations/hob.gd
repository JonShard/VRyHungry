extends StaticBody3D

const RECIPE_MANAGER = preload("res://RecipeManager.gd")

@export var cook_speed = 1
@onready var snap_zone: XRToolsSnapZone = $XRToolsSnapZone
@onready var progress_bar: ProgressBar3D = $ProgressBar3D

var time_cooked = 0
var cooking_result: String
var cooking_result_time = 0 

func _ready() -> void:
	if not progress_bar or progress_bar is not ProgressBar3D:
		push_error("Hob missing reference to progressbar, or wrong type:", progress_bar)
	snap_zone.has_picked_up.connect(_on_object_picked_up)
	snap_zone.has_dropped.connect(_on_object_dropped)
	_refresh_progress_bar()


func _refresh_progress_bar() -> void:
	var progress := 0.0
	if cooking_result and cooking_result_time > 0:
		progress = clampf(float(time_cooked) / cooking_result_time, 0.0, 1.0)

	#print("time_cooked: %s / cooking_result_time: %s =  progress: %s" % [time_cooked, cooking_result_time, progress])
	progress_bar.set_progress(progress)
	progress_bar.set_bar_visible(not cooking_result.is_empty())
	progress_bar.override_fill_color(Color.RED if cooking_result == "charcoal" else Color.GREEN)

func _on_object_picked_up(_item) -> void:
	print("Hob: object picked up: ", _item)

	# Find the CookableItem in held object
	var _food_item = _item.get_node_or_null("FoodItem") as FoodItem
	if not _food_item:
		print("Hob: held object is not a FoodItem")
		return
	var result = RECIPE_MANAGER.get_cooking_result(_food_item.id)
	if not result:
		print("Hob: held a FoodItem that is not cookable, id: %s  result: %s" % [_food_item.id, result])
		return

	cooking_result = result
	cooking_result_time = RECIPE_MANAGER.get_cooking_time(_food_item.id)
	print("Hob: set cooking_result ", cooking_result)
	_refresh_progress_bar()
	$AnimationPlayer.play("hob")


func _on_object_dropped() -> void:
	print("Hob: object drop ")
	$AnimationPlayer.play("RESET")
	time_cooked = 0
	cooking_result = ""
	cooking_result_time = 0
	_refresh_progress_bar()


func convert_held_to_item(_item: String) -> void:
	if not NetworkManager.owns_world():
		return
	print("Hob converting ", _item)
	$AnimationPlayer.play("RESET")
	

	var old_pickable = snap_zone.picked_up_object
	if not old_pickable:
		push_warning("Hob finished cooking _item, but snap zone is missing its reference")
		return

	# Spawn the new item through the server so it replicates to every peer
	# (including late joiners), in the old item's position.
	var original_transform = old_pickable.global_transform
	var new_scene_instance = NetworkManager.spawn_item(RECIPE_MANAGER.get_item_scene(_item).resource_path, original_transform)

	# Drop and free the old item and pick up the new one
	print("Hob freeing old_pickable  ", old_pickable)
	snap_zone.drop_object()
	NetworkManager.despawn_item(old_pickable)
	snap_zone.pick_up_object(new_scene_instance)


# If cooking something, progress cooking, when done, convert item
func _process(delta: float) -> void:
	if cooking_result:
		#print("Hob cooking_result: ", cooking_result)
		time_cooked += cook_speed * delta		
		_refresh_progress_bar()
		if time_cooked >= cooking_result_time:
			time_cooked = 0
			convert_held_to_item(cooking_result)

		
