extends Node3D

@export var target_group : String # Items with this tag can be added to the container
@export var meal_positions: Array[Node3D] = []
@export var side_positions: Array[Node3D] = []

@onready var area_3d: Area3D = $Area3D
@onready var xr_pickable: XRToolsPickable = get_parent() as XRToolsPickable

@onready var _meal_container: Node3D = $MealContainer
@onready var _side_container: Node3D = $SidesContainer

var contained_items: Array[FoodItem] # Expose nice list of others to read


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	area_3d.body_entered.connect(_on_body_entered)
	if not area_3d:
		push_error("Area3D node not found in container.gd")
	if not xr_pickable:
		push_error("XRPickable node not found in container.gd")


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group(target_group):
		return
		
	var picked_by = xr_pickable.get_picked_up_by()
	if picked_by and picked_by.is_in_group("station"):
		
		# If compatible and enough space, add item
		var food_item = body.get_node("FoodItem")
		print("Container in station found %s of type %s: %s" % [target_group, FoodItem.Type.keys()[food_item.type], body.name])
		if food_item.type == FoodItem.Type.MEAL and _meal_container.get_child_count() < meal_positions.size(): 
			print("Container adding meal")
			_add_item(body, meal_positions, _meal_container)
		if food_item.type == FoodItem.Type.SIDE and _side_container.get_child_count() < side_positions.size():
			print("Container adding side")
			_add_item(body, side_positions, _side_container)


func _add_item(item: Node3D, positions: Array[Node3D], container_root: Node3D) -> void:
	var pickable = item as XRToolsPickable
	var rigidbody = item as RigidBody3D
	
	# Drop item
	if pickable:
		if pickable.is_picked_up():
			pickable.drop()
		pickable.enabled = false
	
	# Freeze the rigid body and disable its collisions so it doesn't fight the container
	if rigidbody:
		rigidbody.freeze = true
		rigidbody.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rigidbody.process_mode = PROCESS_MODE_DISABLED
		# Optional: Disable collision layer/mask so it doesn't bump into other food
		rigidbody.collision_layer = 0
		rigidbody.collision_mask = 0
		
	item.reparent(container_root, false) # false = discard global transform
	
	# Get target position index
	var target_slot_index = container_root.get_child_count() - 1
	if target_slot_index < positions.size():
		item.position = positions[target_slot_index].position
		item.rotation = positions[target_slot_index].rotation
	
	# Add to list
	var food_node = item.get_node_or_null("FoodItem")
	if food_node:
		contained_items.append(food_node as FoodItem)

func clear() -> void:
	# delete all nodes in containers and contained_items
	pass


#plate (Pickalbe)
	#XRGrapPoints
	#container (script) (meal positions[1], side positions[4])
		#area
		#meals
			#meal - burger
			#sides
				#side - chips
				#side - onion rings

#tray (Pickalbe)
	#XRGrapPoints
	#container (script) (meal positions[4], side positions[0])
		#food items
		#meals
			#meal - cookie
			#meal - cookie
			#meal - cookie
			#meal - cookie
