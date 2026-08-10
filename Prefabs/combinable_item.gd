class_name CombinableItem
extends Node

@onready var combine_area_3d: Area3D = $Area3d
@onready var _pickable: XRToolsPickable = get_parent() as XRToolsPickable

# Guard so a combine only fires once.
var _combining: bool = false
var _food_item: FoodItem


func _ready() -> void:
	SweetLogger.debug("_ready(): {0}", [_pickable.name], "combinable_item.gd", "_ready")
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
	var is_snapped: bool = by != null and by.has_method("is_xr_class") and by.is_xr_class("XRToolsSnapZone")
	set_deferred("monitoring", is_snapped)

func _on_item_dropped(_item: Node3D) -> void:
	set_deferred("monitoring", false)

# If the other body is a FoodItem, check for a recipe and combine if one exists.
# Combining is a server decision (the base item is server-snapped into a zone).
func _on_body_entered(body: Node3D) -> void:
	if not NetworkManager.owns_world():
		return
	if _combining or body == _pickable:
		SweetLogger.debug("other is our own pickable", [], "combinable_item.gd", "_on_body_entered")
		return

	var other := Helper.find_food_item(body)
	if not other:
		SweetLogger.debug("other is not a foodItem", [], "combinable_item.gd", "_on_body_entered")
		return

	var result: PackedScene = RecipeManager.get_combination_result(_food_item.id, other.id)
	if not result:
		SweetLogger.debug("There is no recipe for {0} + {1}", [_food_item.id, other.id], "combinable_item.gd", "_on_body_entered")
		return

	_combine(body, result)

# Instantiate the result of combination and free the two ingredient items
func _combine(other_body: Node3D, result: PackedScene) -> void:
	SweetLogger.debug("combining {0} + {1} into {2}", [_food_item.id, Helper.find_food_item(other_body).id, result.resource_path], "combinable_item.gd", "_combine")

	# Get Snapzone
	var snap_zone := _pickable.get_picked_up_by()
	if not snap_zone or not snap_zone.has_method("pick_up_object"):
		return

	# Spawn the result through the server (so it replicates to every peer,
	# including late joiners) at the base item's location, in world space.
	var base_transform := _pickable.global_transform
	var result_instance: Node3D = NetworkManager.spawn_item(result.resource_path, base_transform)

	# Free the pickable / root of this item and consume the incoming item.
	snap_zone.drop_object()
	NetworkManager.despawn_item(_pickable)
	other_body.drop()
	NetworkManager.despawn_item(other_body)

	# Snap the result into the now-empty zone.
	snap_zone.pick_up_object(result_instance)
