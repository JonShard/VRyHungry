class_name Helper

# Find a FoodItem among the direct children of [param node].
static func find_food_item(node: Node) -> FoodItem:
	if not node:
		return null
	for child in node.get_children():
		if child is FoodItem:
			return child
	return null
