class_name Helper

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