class_name CombineZone
extends Area3D

## Trigger area that lets a snapped item combine with another item pushed into
## it. The zone only monitors while its owning item is held by an
## [XRToolsSnapZone]; when an item carrying a matching [CombinableItem.id]
## enters, the snapped (base) item transforms into the recipe result and the
## incoming item is consumed.

# The pickable this zone belongs to (its parent).
@onready var _item: XRToolsPickable = get_parent() as XRToolsPickable

# The base item's recipe data.
@onready var _combinable: CombinableItem = _find_combinable(_item)

# Guard so a combine only fires once.
var _combining: bool = false


func _ready() -> void:
	# Detect items whether held (layer 17 "Held Objects") or loose
	# (layer 3 "Pickable Objects"). Don't advertise a layer of our own.
	collision_mask = 0b0000_0000_0000_0001_0000_0000_0000_0100
	collision_layer = 0
	# Deferred: _ready can run during a physics signal flush (when a combine
	# spawns the result), where toggling monitoring directly is forbidden.
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

	if not _item:
		push_error("CombineZone must be a child of an XRToolsPickable.")
		return
	if not _combinable:
		push_error("CombineZone requires a CombinableItem sibling on ", _item.name, ".")
		return

	_item.picked_up.connect(_on_item_picked_up)
	_item.dropped.connect(_on_item_dropped)
	body_entered.connect(_on_body_entered)


# Enable the trigger only while snapped into a snap zone (not hand-held).
func _on_item_picked_up(_pickable: Node3D) -> void:
	var by := _item.get_picked_up_by()
	var snapped: bool = by != null and by.has_method("is_xr_class") and by.is_xr_class("XRToolsSnapZone")
	set_deferred("monitoring", snapped)


func _on_item_dropped(_pickable: Node3D) -> void:
	set_deferred("monitoring", false)


func _on_body_entered(body: Node3D) -> void:
	if _combining or body == _item:
		return

	var other := _find_combinable(body)
	if not other:
		return

	var result: PackedScene = _combinable.get_result_for(other.id)
	if not result:
		return

	_combine(body, result)


# Transform the base item into [param result], consuming the incoming item.
func _combine(other_body: Node3D, result: PackedScene) -> void:
	_combining = true

	var snap_zone := _item.get_picked_up_by()
	if not snap_zone or not snap_zone.has_method("pick_up_object"):
		push_warning("CombineZone: base item is not held by a snap zone; cannot combine.")
		_combining = false
		return

	# Spawn the result at the base item's location, in world space.
	var base_transform := _item.global_transform
	var result_instance: Node3D = result.instantiate()
	_item.get_tree().current_scene.add_child(result_instance)
	result_instance.global_transform = base_transform

	# Free the base item and consume the incoming item.
	snap_zone.drop_object()
	_item.queue_free()
	if other_body.has_method("drop_and_free"):
		other_body.drop_and_free()
	else:
		other_body.queue_free()

	# Snap the result into the now-empty zone.
	snap_zone.pick_up_object(result_instance)


# Find a CombinableItem among the direct children of [param node].
func _find_combinable(node: Node) -> CombinableItem:
	if not node:
		return null
	for child in node.get_children():
		if child is CombinableItem:
			return child
	return null
