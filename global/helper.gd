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


# Returns "script.gd::caller_function" of whoever originally called into Helper, skipping recursive self-calls.
static func _get_caller_label() -> String:
	var stack := get_stack()
	# stack[0] = _get_caller_label, stack[1] = the Helper function that called this
	var self_function: String = stack[1].function if stack.size() > 1 else ""
	var caller_index := 2
	while caller_index < stack.size() and stack[caller_index].function == self_function:
		caller_index += 1
	if caller_index >= stack.size():
		return "unknown"
	var caller_script: String = (stack[caller_index].source as String).get_file()
	return "{0}::{1}".format([caller_script, stack[caller_index].function])


static func find_first_child_of_type(node: Node, type: Variant) -> Node:
	for child in node.get_children():
		if is_instance_of(child, type):
			return child
		var nested := find_first_child_of_type(child, type)
		if nested:
			return nested
	#SweetLogger.warning("{0}: Could not find child of type {1} from node at: {2}", [_get_caller_label(), type.get_global_name(), node.get_path()])
	return null


# Returns true if decendant is a decendant node of root, false otherwise. Returns false if either node is null.
static func is_node_decendant_of(decendant: Node, root: Node) -> bool:
	if not decendant or not root:
		SweetLogger.debug("{0}: Decendant or root is null", [_get_caller_label()])
		return false
	var current: Node = decendant
	while current:
		if current == root:
			SweetLogger.debug("{0}: Decendant {1} is a descendant of root {2}", [_get_caller_label(), decendant.name, root.name])
			return true
		current = current.get_parent()
	SweetLogger.debug("{0}: Decendant {1} is NOT a descendant of root {2}", [_get_caller_label(), decendant.name, root.name])
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

static func get_node_from_path(from: Node, node_path: NodePath) -> Node3D:
	var item := from.get_node_or_null(node_path) as Node3D
	if not item:
		SweetLogger.warning("{0}: Could not resolve node from node_path: {1}, are the trees in sync?", [_get_caller_label(), node_path])
		return null
	return item



static func check_reference(node: Node, ref: Variant, type: Variant) -> bool:
	if is_instance_valid(ref) and is_instance_of(ref, type):
		return true
	var type_name: String
	if type is Script:
		type_name = type.get_global_name()
	else:
		var probe: Object = type.new()
		type_name = probe.get_class()
		if not (probe is RefCounted):
			probe.free()
	SweetLogger.warning("{0} missing reference {1} ({2})", [node.name, type_name, _get_caller_label()])
	return false



static func play_sound(player: AudioStreamPlayer3D, stream: AudioStream, pitch_scale: float = 1):
	if not player:
		SweetLogger.warning("{0}: AudioStreamPlayer3D is null, can not play sound", [_get_caller_label()])
		return
	if not stream:
		SweetLogger.warning("{0}: AudioStream is null, can not play sound", [_get_caller_label()])
		return
	player.pitch_scale = pitch_scale
	player.stream = stream
	player.play()
	SweetLogger.debug("{0}: Play sound: {1} with pitch_scale: {2} on {3}", [_get_caller_label(), stream.resource_path, pitch_scale, player.get_parent().name])
