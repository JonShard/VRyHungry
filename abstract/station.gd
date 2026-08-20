class_name Station
extends Node3D

### Abstract 'class', should never be instantiated ###
# - Keep all logic all stations share.
# - Contain as much of the networking code syncing stations as possible.

## Sounds
@export var pickup_sound: AudioStream
@export var drop_sound: AudioStream

## Node references. These are all required snd should be set in the inspector
@export var notification_audio: AudioStreamPlayer3D # Short sounds like pickup or complete
@export var ambient_audio: AudioStreamPlayer3D # Releating sounds like a cooking noise
@export var snap_zone: XRToolsSnapZone
@export var synchronizer: MultiplayerSynchronizer

var sync_config: SceneReplicationConfig

var enabled: bool: # When disabled the station only updated display and sounds.
	get: return snap_zone.enabled
	set(p_enabled):
		SweetLogger.debug("Set enabled {0} on station {1} on client {2}", [p_enabled, name, multiplayer.get_unique_id()])
		snap_zone.enabled = p_enabled
		snap_zone.set_process(p_enabled)


# Godot requires replication_config to be fully built before _ready. So in _enter_tree
# The child station has to call super._enter_tree() for this to be called.
func _enter_tree() -> void:
	# Always a fresh config - abstract/station.tscn's config sub-resource is shared
	# in memory across every station scene that instances it, so reusing it here
	# would pile every station type's properties onto the same shared object.
	synchronizer.root_path = get_path()
	synchronizer.replication_config = SceneReplicationConfig.new()
	sync_config = synchronizer.replication_config


# The child station has to call super.ready() for this to be called
func ready() -> void:
	SweetLogger.debug("Station {0} ready", [name])
	if not notification_audio:
		SweetLogger.warning("{0} missing notification_audio reference", [name])
	if not ambient_audio:
		SweetLogger.warning("{0} missing ambient_audio reference", [name])
	if not snap_zone:
		SweetLogger.warning("{0} missing snap_zone reference", [name])
	if not synchronizer:
		SweetLogger.warning("{0} missing synchronizer reference", [name])
	# Disable if we're not the server.
	if not NetworkManager.owns_world():
		enabled = false

	snap_zone.has_picked_up.connect(_on_object_picked_up_handler)
	snap_zone.has_dropped.connect(_on_object_dropped_handler)

# The child station has to call super.process(delta) for this to be called
func process(_delta: float) -> void:
	refresh_display()


## Signal handles ##
func _on_object_picked_up_handler(item: Node3D) -> void:
	if not NetworkManager.owns_world():
		return
	_clients_on_object_picked_up_handler.rpc(item.get_path())
	_apply_object_picked_up(item)


func _on_object_dropped_handler(item: Node3D) -> void:
	if not NetworkManager.owns_world():
		return
	_clients_on_object_dropped_handler.rpc(item.get_path())
	_apply_object_dropped(item)


func _apply_object_picked_up(item: Node3D) -> void:
	SweetLogger.info("{0}: Pickup: {1}", [name, item.name])
	Helper.play_sound(notification_audio, pickup_sound)
	on_object_picked_up(item)
	var food_item = Helper.find_food_item(item)
	if food_item:
		on_food_item_picked_up(food_item)


func _apply_object_dropped(item: Node3D) -> void:
	Helper.play_sound(notification_audio, drop_sound, 0.8)
	SweetLogger.info("{0}: Drop: {1}", [name, item.name])
	on_object_dropped(item)
	var food_item = Helper.find_food_item(item)
	if food_item:
		on_food_item_dropped(food_item)


# Propagate events to clients
@rpc("authority", "call_remote", "reliable")
func _clients_on_object_picked_up_handler(item_path: NodePath):
	var item := Helper.get_node_from_path(self, item_path) as Node3D
	if not item:
		return
	_apply_object_picked_up(item)

@rpc("authority", "call_remote", "reliable")
func _clients_on_object_dropped_handler(item_path: NodePath):
	var item := Helper.get_node_from_path(self, item_path) as Node3D
	if not item:
		return
	_apply_object_dropped(item)



## Virutal methods
# The child station implements these if it cares about them.
func on_object_picked_up(_item: Node3D) -> void:
	pass

func on_object_dropped(_item: Node3D) -> void:
	pass

func on_food_item_picked_up(_food_item: FoodItem) -> void:
	pass

func on_food_item_dropped(_food_item: FoodItem) -> void:
	pass

func refresh_display() -> void:
	pass
