extends StaticBody3D


@export var cook_speed = 1
@onready var snap_zone: XRToolsSnapZone = $XRToolsSnapZone

var item = null
var progress = 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if snap_zone.initial_object:
		item = snap_zone.initial_object
		print("Hob has item: ", item)
	else:
		print("Hob is empty")

func convert_item(cookable: CookableItem) -> void:
	print("Hob converting ", cookable)
	
	var old_pickable = snap_zone.picked_up_object
	if not old_pickable:
		push_warning("Hob finished cooking item, but snap zone is missing its reference")
		return
	
	print("picked_up_object ", snap_zone.picked_up_object)

	var original_transform = old_pickable.global_transform
	var new_scene_instance = cookable.turns_into.instantiate()
	
	# Add the new item to the hob's parent (so it lives in the main world space)
	get_parent().add_child(new_scene_instance)
	new_scene_instance.global_transform = original_transform

	snap_zone.drop_object() 
	print("old_pickable  ", old_pickable)
	old_pickable.queue_free()
	snap_zone.pick_up_object(new_scene_instance)
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:	
	# Find the CookableItem in held object
	var cookable = null
	if snap_zone.picked_up_object:
		var matches = snap_zone.picked_up_object.get_children().filter(func(c): return c is CookableItem)
		if matches.size() > 0:
			cookable = matches[0]
	
	# Cook it if exists, then convert item after cooking
	if cookable:
		progress += cook_speed * delta
		print("Cooking ", progress)
		if progress >= cookable.cooking_time:
			progress = 0
			convert_item(cookable)
	else:
		progress = 0
		
