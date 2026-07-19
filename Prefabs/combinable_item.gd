class_name CombinableItem
extends Node

const RECIPE_MANAGER = preload("res://RecipeManager.gd")

@onready var combine_area_3d: Area3D = $Area3d
@onready var _pickable: XRToolsPickable = get_parent() as XRToolsPickable

# Guard so a combine only fires once.
var _combining: bool = false
var _food_item: FoodItem


func _ready() -> void:
	print("CombinableItem _ready(): ", _pickable.name)
	_food_item = get_parent().get_node_or_null("FoodItem") as FoodItem
	if not _food_item:
		push_error("CombinableItem is missing FoodItem reference. must be a sibling of a FoodItem on ", get_parent().name, ".")

	if not _pickable:
		push_error("CombineZone must be a grand child of an XRToolsPickable.")
		return
	if not _food_item:
		push_error("CombineZone requires a FoodItem sibling on ", _pickable.name, ".")
		return

	# Detect items whether held (layer 17 "Held Objects") or loose
	# (layer 3 "Pickable Objects"). Don't advertise a layer of our own.
	combine_area_3d.collision_mask = 0b0000_0000_0000_0001_0000_0000_0000_0100
	combine_area_3d.collision_layer = 0
	# Deferred: _ready can run during a physics signal flush (when a combine
	# spawns the result), where toggling monitoring directly is forbidden.
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

	# Signals
	_pickable.picked_up.connect(_on_item_picked_up)
	_pickable.dropped.connect(_on_item_dropped)
	combine_area_3d.body_entered.connect(_on_body_entered)


# Enable the trigger only while snapped into a snap zone (not hand-held).
func _on_item_picked_up(_item: Node3D) -> void:
	var by := _pickable.get_picked_up_by()
	var snapped: bool = by != null and by.has_method("is_xr_class") and by.is_xr_class("XRToolsSnapZone")
	set_deferred("monitoring", snapped)

func _on_item_dropped(_item: Node3D) -> void:
	set_deferred("monitoring", false)

# If the other body is a FoodItem, check for a recipe and combine if one exists.
func _on_body_entered(body: Node3D) -> void:
	if _combining or body == _pickable:
		print("CombinableItem _on_body_entered: other is our own pickable")
		return

	var other := _find_food_item(body)
	if not other:
		print("CombinableItem _on_body_entered: other is not a foodItem")
		return

	var result: PackedScene = RECIPE_MANAGER.get_combination_result(_food_item.id, other.id)
	if not result:
		print("CombinableItem _on_body_entered: There is no recipe for %s + %s" % [_food_item.id, other.id])
		return

	_combine(body, result)

# Instantiate the result of combination and free the two ingredient items
func _combine(other_body: Node3D, result: PackedScene) -> void:
	print("CombinableItem _combine: combining %s + %s into %s" % [_food_item.id, _find_food_item(other_body).id, result.resource_path])
	_combining = true

	# Get Snapzone
	var snap_zone := _pickable.get_picked_up_by()
	if not snap_zone or not snap_zone.has_method("pick_up_object"):
		push_warning("CombineZone: base item is not held by a snap zone; cannot combine.")
		_combining = false
		return

	# Spawn the result at the base item's location, in world space.
	var base_transform := _pickable.global_transform
	var result_instance: Node3D = result.instantiate()
	_pickable.get_tree().current_scene.add_child(result_instance)
	result_instance.global_transform = base_transform

	# Free the pickable / root of this item and consume the incoming item.
	snap_zone.drop_object()
	_pickable.queue_free()
	if other_body.has_method("drop_and_free"): # XRToolsPickable has this method
		other_body.drop_and_free()
	else:
		other_body.queue_free()

	# Snap the result into the now-empty zone.
	snap_zone.pick_up_object(result_instance)


# Find a FoodItem among the direct children of [param node].
func _find_food_item(node: Node) -> FoodItem:
	if not node:
		return null
	for child in node.get_children():
		if child is FoodItem:
			return child
	return null
