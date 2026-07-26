class_name ItemContainer
extends Node3D

@export var enabled: bool = true
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


# Absorbing items is a server decision (the container's holder is server-
# snapped into a station, matching table.gd/hob.gd's convention).
func _on_body_entered(body: Node3D) -> void:
	if not NetworkManager.owns_world():
		return
	print("Container enabled: ", enabled)
	if not enabled:
		print("Container disabled in  _on_body_entered body")
		return
	if not body.is_in_group(target_group):
		return
	print("Container _on_body_entered body: ", body)
	var picked_by = xr_pickable.get_picked_up_by()
	if picked_by and picked_by.is_in_group("station"):

		# If compatible and enough space, add item
		var food_item = body.get_node("FoodItem")
		print("Container in station found %s of type %s: %s" % [target_group, FoodItem.Type.keys()[food_item.type], body.name])
		var meal_count := contained_items.filter(func(f): return f.type == FoodItem.Type.MEAL).size()
		var side_count := contained_items.filter(func(f): return f.type == FoodItem.Type.SIDE).size()
		if food_item.type == FoodItem.Type.MEAL and meal_count < meal_positions.size():
			print("Container adding meal")
			_add_item(body)
		if food_item.type == FoodItem.Type.SIDE and side_count < side_positions.size():
			print("Container adding side")
			_add_item(body)


# Contents are synced as data (ids on the plate's PlateController), not
# reparented nodes: reparenting a MultiplayerSpawner-tracked item out of
# WorldContent would despawn it on every client the instant it happened.
func _add_item(item: Node3D) -> void:
	var pickable = item as XRToolsPickable
	if pickable and pickable.is_picked_up():
		pickable.drop()

	var food_node := item.get_node_or_null("FoodItem") as FoodItem
	if not food_node:
		return

	# Copy the data out before despawning the real item.
	var data := FoodItem.new()
	data.id = food_node.id
	data.type = food_node.type
	data.sell_value = food_node.sell_value
	contained_items.append(data)

	var plate_controller := xr_pickable.get_node_or_null("PlateController") as PlateController
	if plate_controller:
		# Reassign rather than append in place. contained_ids has a setter that
		# rebuilds the plate's visuals, and mutating the array never triggers it —
		# so the peer that actually added the food was the one peer that never
		# redrew the plate. Remote peers looked right (the synchronizer assigns
		# the value there, which does fire the setter), and the stale peer only
		# caught up if someone else took the plate and sent the value back.
		# duplicate() keeps the Array[String] typing that the property requires.
		var updated := plate_controller.contained_ids.duplicate()
		updated.append(food_node.id)
		plate_controller.contained_ids = updated

	NetworkManager.despawn_item(item)


func erase_item(item: FoodItem) -> void:
	contained_items.erase(item)
	var plate_controller := xr_pickable.get_node_or_null("PlateController") as PlateController
	if plate_controller:
		# Same reason as _add_item: assign so the visuals actually refresh.
		var remaining := plate_controller.contained_ids.duplicate()
		remaining.erase(item.id)
		plate_controller.contained_ids = remaining


func clear() -> void:
	contained_items.clear()
	var plate_controller := xr_pickable.get_node_or_null("PlateController") as PlateController
	if plate_controller:
		plate_controller.contained_ids = []


## Rebuilds the purely-cosmetic visual representation of the plate's contents
## from a synced id list. Runs on every peer (called from PlateController
## whenever contained_ids changes, whether set locally or by the network).
func refresh_visuals(ids: Array[String]) -> void:
	for child in _meal_container.get_children():
		child.queue_free()
	for child in _side_container.get_children():
		child.queue_free()

	var meal_idx := 0
	var side_idx := 0
	for id in ids:
		var scene := RecipeManager.get_item_scene(id)
		if not scene:
			continue
		var visual := scene.instantiate()
		var food_node := visual.get_node_or_null("FoodItem") as FoodItem

		var container_root: Node3D
		var positions: Array[Node3D]
		var idx: int
		if food_node and food_node.type == FoodItem.Type.MEAL and meal_idx < meal_positions.size():
			container_root = _meal_container
			positions = meal_positions
			idx = meal_idx
			meal_idx += 1
		elif food_node and food_node.type == FoodItem.Type.SIDE and side_idx < side_positions.size():
			container_root = _side_container
			positions = side_positions
			idx = side_idx
			side_idx += 1
		else:
			visual.queue_free()
			continue

		_make_cosmetic(visual)
		container_root.add_child(visual)
		visual.position = positions[idx].position
		visual.rotation = positions[idx].rotation


# Strip interactivity/networking from a display-only copy: it's not spawned
# through NetworkManager, so it must never try to sync (its NetPickable child,
# if any, would have no corresponding replicated identity on other peers) or
# be grabbable/collidable.
func _make_cosmetic(visual: Node3D) -> void:
	var net_pickable := visual.get_node_or_null("NetPickable")
	if net_pickable:
		net_pickable.queue_free()
	if visual is RigidBody3D:
		visual.freeze = true
		visual.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		visual.collision_layer = 0
		visual.collision_mask = 0
	if visual is XRToolsPickable:
		visual.enabled = false
	visual.set_process(false)
	visual.set_physics_process(false)


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
