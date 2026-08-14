extends Node
class_name BuildModeController

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Signals.game_state_changed.connect(_on_game_state_changed)


func _on_game_state_changed(new_state: GameManager.GameState) -> void:
	SweetLogger.info("Game state changed to {0}", [GameManager.GameState.keys()[new_state]], "build_mode_controller.gd", "_on_game_state_changed")
	if new_state == GameManager.GameState.BUILDING:
		despawn_unheld_pickables()
	if not NetworkManager.owns_world():
		return
	if new_state == GameManager.GameState.BUILDING:
		_set_stations_enabled(false)
	elif new_state == GameManager.GameState.RUNNING:
		_set_stations_enabled(true)


# Only Station-derived stations expose `enabled` (Table runs its own FSM).
func _set_stations_enabled(value: bool) -> void:
	for station in get_tree().get_nodes_in_group("station"):
		if station is Station:
			station.enabled = value


# Despawn all food_items unless it's in a "persistent_inventory" snap_zone
func despawn_unheld_pickables():
	var root = get_tree().get_root()
	var pickables: Array[Node] = []
	_collect_pickables(root, pickables)
	for pickable in pickables:
		if not Helper.find_food_item(pickable):
			continue
		var held_by: Node = pickable.get_picked_up_by()
		if not held_by:
			NetworkManager.despawn_item(pickable)
			continue
		if not held_by.is_in_group("persistent_inventory"):
			SweetLogger.debug("Despawn unheld pickable held_by: {0}, pickable: {1}", [held_by, pickable])
			pickable.drop()
			NetworkManager.despawn_item(pickable)
			

func _collect_pickables(node: Node, out_array: Array) -> void:
	if node is XRToolsPickable:
		out_array.append(node)
	for child in node.get_children():
		if child is Node:
			_collect_pickables(child, out_array)
