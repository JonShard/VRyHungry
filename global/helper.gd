class_name Helper

const SNAP_GRID_SIZE = 0.6


# Find a FoodItem among the direct children of [param node].
static func find_food_item(node: Node) -> FoodItem:
	if not node:
		return null
	for child in node.get_children():
		if child is FoodItem:
			return child
	return null


static func find_first_child_of_type(node: Node, type: Variant) -> Node:
	for child in node.get_children():
		if is_instance_of(child, type):
			return child
		var nested := find_first_child_of_type(child, type)
		if nested:
			return nested
	return null
	
# Returns true if decendant is a decendant node of root, false otherwise. Returns false if either node is null.
static func is_node_decendant_of(decendant: Node, root: Node) -> bool:
	if not decendant or not root:
		SweetLogger.debug("is_node_decendant_of: decendant or root is null")
		return false
	var current: Node = decendant
	while current:
		if current == root:
			SweetLogger.debug("is_node_decendant_of: decendant {0} is a descendant of root {1}", [decendant.name, root.name])
			return true
		current = current.get_parent()
	SweetLogger.debug("is_node_decendant_of: decendant {0} is NOT a descendant of root {1}", [decendant.name, root.name])
	return false
	

# Returns a transform with position snapped to the 0.6 grid and rotation snapped to 90 degrees.
static func get_snapped_transform(node: Node3D) -> Transform3D:
	var new_transform: Transform3D
	new_transform.origin.x = snappedf(node.global_position.x, SNAP_GRID_SIZE)
	new_transform.origin.z = snappedf(node.global_position.z, SNAP_GRID_SIZE)
	new_transform.origin.y = node.global_position.y
	var target_yaw: float = snappedf(node.global_rotation_degrees.y, 90)
	new_transform.basis = Basis(Vector3.UP, deg_to_rad(target_yaw))
	return new_transform
