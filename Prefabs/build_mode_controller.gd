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


# Only single-snap_zone Station-derived stations use the generic `enabled`
# toggle here. Table is Station-derived too now (SharedInventoryStation), but
# it has multiple snap_zones and manages their enabling itself via its own
# FSM (_set_snap_zones_enabled) - toggling only the base `snap_zone` here
# would desync it from the rest of Table's zones, so it's excluded.
func _set_stations_enabled(value: bool) -> void:
	for station in get_tree().get_nodes_in_group("station"):
		if station is Station and not station is Table:
			station.enabled = value


# Despawn all despawnable pickables unless it's in a "persistent_inventory"
# snap_zone. Permanent fixtures (e.g. a station's knife) opt out entirely by
# having no DespawningItem child, or a disabled one.
func despawn_unheld_pickables():
	var root = get_tree().get_root()
	var pickables: Array[Node] = []
	_collect_pickables(root, pickables)
	for pickable in pickables:
		var despawning_item := pickable.get_node_or_null("DespawningItem") as DespawningItem
		if not despawning_item or not despawning_item.enabled:
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
