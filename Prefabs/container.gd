extends Node3D

@export var target_group : String # Items with this tag can be added to the container
@export var meal_positions: Array[Node3D] = []
@export var side_positions: Array[Node3D] = []

@onready var area_3d: Area3D = $Area3D
@onready var xr_pickable: XRToolsPickable = get_parent() as XRToolsPickable

@onready var _meal_container: Node3D = $MealContainer
@onready var _sides_container: Node3D = $SidesContainer

var contained_items: Array[FoodItem]

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	area_3d.body_entered.connect(_on_body_entered)
	if not area_3d:
		push_error("Area3D node not found in container.gd")
	if not xr_pickable:
		push_error("XRPickable node not found in container.gd")


func _on_body_entered (body) -> void:
	if not body.is_in_group(target_group):
		return
	print("Body is platable: %s" % body.name)
	var picked_by = xr_pickable.get_picked_up_by()
	if picked_by and picked_by.is_in_group("station"):
		print("Container in station")
		var food_item = get_node("FoodItem") 
		if food_item.type == FoodItem.Type.MEAL or food_item.type == FoodItem.Type.SIDE:
			# if we're full of that type:
			# return 
			# body disble pickable
			# container parent to self
			# body set position to apropriate slot
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
