class_name SharedInventoryStation
extends Station

### Abstract 'class', should never be instantiated ###
# Backbone for stations that need to know about neighboring stations of the
# same kind (tables, belts).

## Path to one Area3D probe per direction this station should watch for a
## same-kind neighbor. Wired explicitly per concrete scene (e.g. a belt
## wires one path, a table wires four).
@export var probe_paths: Array[NodePath] = []

## Resolved from probe_paths in ready().
var probes: Array[Area3D] = []

## Area3D probe -> the SharedInventoryStation neighbor detected through it
## (or null if that direction is currently unoccupied).
var neighbors: Dictionary = {}


# The child station has to call super._enter_tree() for this to be called
func _enter_tree() -> void:
	super._enter_tree()
	var properties: Array[NodePath] = [".:position", ".:rotation", ".:visible"]
	for property_path in properties:
		sync_config.add_property(property_path)
		sync_config.property_set_spawn(property_path, false)
		sync_config.property_set_replication_mode(property_path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)


# The child station has to call super.ready() for this to be called
func ready() -> void:
	super.ready()
	# Find probes
	for path in probe_paths:
		var probe := get_node_or_null(path) as Area3D
		if probe:
			probes.append(probe)
		else:
			SweetLogger.warning("{0} could not resolve neighbor probe at path {1}", [name, path])
	if probes.is_empty():
		SweetLogger.warning("{0} has no neighbor probes wired", [name])
	for probe in probes:
		neighbors[probe] = null
		probe.body_entered.connect(_on_probe_body_entered.bind(probe))
		probe.body_exited.connect(_on_probe_body_exited.bind(probe))
	# Init leader state before any probe signal has a chance to fire
	_broadcast_group_changed.call_deferred()


## Cycle-safe search of the neighbor graph (handles circular belt/table loops)
func get_connected_group() -> Array[SharedInventoryStation]:
	var visited: Dictionary = {get_instance_id(): true}
	var queue: Array[SharedInventoryStation] = [self]
	var group: Array[SharedInventoryStation] = []
	while not queue.is_empty():
		var current: SharedInventoryStation = queue.pop_front()
		group.append(current)
		for neighbor in current.neighbors.values():
			if neighbor and not visited.has(neighbor.get_instance_id()):
				visited[neighbor.get_instance_id()] = true
				queue.append(neighbor)
	return group


## Deterministic leader: smallest grid position, computed the same on every peer
func is_group_leader() -> bool:
	var leader: SharedInventoryStation = self
	for member in get_connected_group():
		if _grid_sort_key(member) < _grid_sort_key(leader):
			leader = member
	return leader == self


static func _grid_sort_key(station: SharedInventoryStation) -> Vector2i:
	var pos := station.global_position
	return Vector2i(roundi(pos.x / Helper.SNAP_GRID_SIZE), roundi(pos.z / Helper.SNAP_GRID_SIZE))


## Food items this station holds, exposed for neighbors to read; override for multi-zone stations
func get_exposed_food_items() -> Array[FoodItem]:
	var items: Array[FoodItem] = []
	if snap_zone and snap_zone.picked_up_object:
		var food_item := Helper.find_food_item(snap_zone.picked_up_object)
		if food_item:
			items.append(food_item)
	return items


## Every food item held anywhere in this station's connected group
func get_group_food_items() -> Array[FoodItem]:
	var items: Array[FoodItem] = []
	for member in get_connected_group():
		items.append_array(member.get_exposed_food_items())
	return items


func _on_probe_body_entered(body: Node3D, probe: Area3D) -> void:
	var station := body as SharedInventoryStation
	if not station or station == self:
		return
	neighbors[probe] = station
	_broadcast_group_changed()


func _on_probe_body_exited(body: Node3D, probe: Area3D) -> void:
	var former: SharedInventoryStation = neighbors.get(probe)
	if not former or body != former:
		return
	neighbors[probe] = null
	# former is no longer reachable from self, so it needs telling separately
	former._broadcast_group_changed()
	_broadcast_group_changed()


## Notifies every member of this station's current connected group (not just the two that changed)
func _broadcast_group_changed() -> void:
	for member in get_connected_group():
		member._on_group_changed()


## Virtual hook: override to react to this station's group membership/leadership changing
func _on_group_changed() -> void:
	pass
