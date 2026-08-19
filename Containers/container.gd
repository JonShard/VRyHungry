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

# Item roots the server has promised a slot to but whose absorb RPC hasn't run
# yet. body_entered fires again for a body already inside the area whenever its
# collision_mask is rewritten — which apply_held_state() does the moment item
# authority moves back to the server, i.e. exactly when a client drops food on a
# plate. Both calls would otherwise see the same free slot and absorb twice.
# Keyed on the item root / pickable.
var _pending_absorb: Array[Node3D] = []

func _ready() -> void:
	area_3d.body_entered.connect(_on_body_entered)
	if not area_3d:
		SweetLogger.warning("{0} missing area_3d reference", [name])
	if not xr_pickable:
		SweetLogger.warning("{0} missing xr_pickable reference", [name])


# Absorbing items is a server decision (the container's holder is server-
# snapped into a station, matching table.gd/hob.gd's convention).
func _on_body_entered(body: Node3D) -> void:
	if not NetworkManager.owns_world():
		return
	if not enabled:
		SweetLogger.debug("Disabled in _on_body_entered body")
		return
	if not body.is_in_group(target_group):
		SweetLogger.debug("{0} is not in group {1}", [body.name, target_group])
		return
	SweetLogger.debug("Body: {0}", [body])

	# If one of us is in a station
	var picked_by = xr_pickable.get_picked_up_by()
	var body_pickable = body as XRToolsPickable
	var body_picked_by = body_pickable.get_picked_up_by() if body_pickable else null
	if (picked_by and picked_by.is_in_group("station_zone")) or (body_picked_by and body_picked_by.is_in_group("station_zone")):

		# If enough space, add item
		var food_item = Helper.find_food_item(body) as FoodItem
		SweetLogger.debug("In station found {0} of type {1}: {2}", [target_group, FoodItem.Type.keys()[food_item.type], body.name], "container.gd", "_on_body_entered")
		SweetLogger.debug("{0} pending={1} contained={2}", [get_path(), _pending_absorb.size(), contained_items.size()])
		if body in _pending_absorb or _is_contained(body):
			SweetLogger.debug("{0} is already in {1}", [body.name, get_parent().name])
			return
		if food_item.type == FoodItem.Type.MEAL and _free_slots(FoodItem.Type.MEAL) > 0:
			SweetLogger.info("{0}, Adding meal", [name])
			_add_item(body, food_item)
		if food_item.type == FoodItem.Type.SIDE and _free_slots(FoodItem.Type.SIDE) > 0:
			SweetLogger.info("{0}, Adding side", [name])
			_add_item(body, food_item)


# Already sitting in one of this container's slots.
func _is_contained(item: Node3D) -> bool:
	return item.get_parent() == _meal_container or item.get_parent() == _side_container


# Room left for [param type], counting slots already promised to items whose
# absorb RPC hasn't landed yet.
func _free_slots(type: FoodItem.Type) -> int:
	var is_meal := type == FoodItem.Type.MEAL
	var used := (_meal_container if is_meal else _side_container).get_child_count()
	for item in _pending_absorb:
		var food_item := Helper.find_food_item(item)
		if food_item and food_item.type == type:
			used += 1
	return (meal_positions if is_meal else side_positions).size() - used


func _add_item(item: Node3D, food_item: FoodItem) -> void:
	SweetLogger.debug("->[]")
	# Claim the slot now: the RPC below only runs once the current frame's
	# signal handlers have all had their turn.
	_pending_absorb.append(item)
	everyone_absorb_item.rpc(item.get_path())

	# In case the container is on a table that needs to register this addition,
	# ask all table in scene to absorb any new items.
	SweetLogger.debug("Group call absorb_items()")
	get_tree().call_group("table", "absorb_items")


## Runs on every peer: the item stops being an independent networked object and
## becomes a child of this container, carried by the container's transform.
@rpc("authority", "call_local", "reliable")
func everyone_absorb_item(item_path: NodePath) -> void:
	var item := Helper.get_node_from_path(self, item_path) as Node3D
	if not item:
		SweetLogger.error("Container cant find item")
		return
	var food_item := Helper.find_first_child_of_type(item, FoodItem) as FoodItem
	if not food_item:
		SweetLogger.error("Container cant find food item")
		return
	# The reservation is now being honoured (or is about to be refused); either way it
	# stops holding a slot from here on.
	_pending_absorb.erase(item)
	if _is_contained(item):
		SweetLogger.warning("{0} is already in {1}", [item.name, get_parent().name])
		return

	# Pick the slot 
	var target: Node3D
	var slot: Node3D
	if food_item.type == FoodItem.Type.MEAL and _meal_container.get_child_count() < meal_positions.size():
		target = _meal_container
		slot = meal_positions[_meal_container.get_child_count()]
	elif food_item.type == FoodItem.Type.SIDE and _side_container.get_child_count() < side_positions.size():
		target = _side_container
		slot = side_positions[_side_container.get_child_count()]
	else:
		SweetLogger.error("{0}: no free slot for {1}", [name, item.name])
		return

	_hand_over_to_container(item)
	item.reparent(target, false) # keep_global_transform=false: the slot is expressed in container-local space
	item.position = slot.position
	item.rotation = slot.rotation
	# After the reparent, not before: re-entering the tree puts the body back
	# into the physics space, so it can only be taken out again once it's there.
	_remove_from_physics(item)

	contained_items.append(food_item)
	_publish_contained_ids()
	SweetLogger.info("{0} absorbed {1}, contained_items: {2}", [get_parent().name, item.name, contained_items.size()])


## Server decision, mirrored to every peer.
func erase_item(item: FoodItem) -> void:
	if not NetworkManager.owns_world():
		return
	everyone_erase_item.rpc(item.get_parent().get_path())


@rpc("authority", "call_local", "reliable")
func everyone_erase_item(item_path: NodePath) -> void:
	var item := Helper.get_node_from_path(self, item_path) as Node3D
	if not item:
		return
	contained_items.erase(Helper.find_first_child_of_type(item, FoodItem))
	item.queue_free()
	_publish_contained_ids()


## Server decision, mirrored to every peer.
func clear() -> void:
	if not NetworkManager.owns_world():
		return
	everyone_clear.rpc()


@rpc("authority", "call_local", "reliable")
func everyone_clear() -> void:
	for child in _meal_container.get_children() + _side_container.get_children():
		child.queue_free()
	contained_items.clear()
	_publish_contained_ids()


# Hand the item over to the container: from here on the container's parent (e.g.
# a plate a client is carrying with local authority) is the only thing that
# decides where the item is, so it must stop behaving as a pickable and stop
# replicating a transform of its own.
func _hand_over_to_container(item: Node3D) -> void:
	var pickable := item as XRToolsPickable
	if pickable:
		if pickable.is_picked_up():
			pickable.drop()
		pickable.enabled = false
	var net_pickable := item.get_node_or_null("NetPickable") as NetPickable
	if net_pickable:
		net_pickable.transform_owned = false
	else:
		SweetLogger.error("{0}: {1} has no NetPickable", [name, item.name])
	var despawning := Helper.find_first_child_of_type(item, DespawningItem) as DespawningItem
	if despawning:
		despawning.enabled = false


# Take the item out of the physics simulation entirely so it simply follows its
# new parent.
#
# Freezing is not enough. Under Jolt (this project's physics engine) a frozen
# KINEMATIC RigidBody3D is still simulated: it is driven toward its target
# transform by velocity rather than being teleported. Parented to a plate that
# gets picked up and carried, it therefore lags behind, keeps its velocity and
# overshoots — the food visibly slid off the plate, differently on each peer.
# A body with no space is never touched by the engine.
func _remove_from_physics(item: Node3D) -> void:
	var body := item as RigidBody3D
	if not body:
		return
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	body.freeze = true
	body.collision_layer = 0
	body.collision_mask = 0
	PhysicsServer3D.body_set_space(body.get_rid(), RID())


# The contents are real child nodes now; contained_ids is just the synced
# summary that the plate's UI and the multiplayer tests read.
func _publish_contained_ids() -> void:
	var plate_controller := xr_pickable.get_node_or_null("PlateController") as PlateController
	if not plate_controller:
		return
	var ids: Array[String] = []
	for food_item in contained_items:
		ids.append(food_item.id)
	plate_controller.contained_ids = ids
	SweetLogger.debug("{0} now contains: {1}", [get_parent().name, ids])
