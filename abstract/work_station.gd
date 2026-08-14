class_name WorkStation
extends Station

### Abstract 'class', should never be instantiated ###
# This script serves two main jobs:
# - Keep all logic all workstations (sink, hob...) share.
# - Contain as much of the networking code syncing stations as possible.

## Sounds
@export var process_sound: AudioStream
@export var complete_sound: AudioStream

## Node references. These are all required snd should be set in the inspector
@export var notification_audio: AudioStreamPlayer3D # Short sounds like pickup or complete
@export var ambient_audio: AudioStreamPlayer3D # Releating sounds like a cooking noise
@export var progress_bar: ProgressBar3D


## Synced by MultiplayerSyncronizer ##
var current_work: float # How far a FoodItem conversion is toward completion
var max_work: float     # How much work has to be acheived to trigger conversion
var result_id: String # Station active if not empty. What FoodItem id the conversion turns the current FoodItem into.

# The child station has to call super.ready() for this to be called
func ready() -> void:
	super.ready()
	if not notification_audio:
		SweetLogger.warning("{0} missing notification_audio reference", [name])
	if not ambient_audio:
		SweetLogger.warning("{0} missing ambient_audio reference", [name])
	if not progress_bar:
		SweetLogger.warning("{0} missing progress_bar reference", [name])

	# Configure Multiplayer Syncronizer
	# Base Station creates the config, here we append to it:
	var properties: Array[NodePath] = [ ".:current_work", ".:max_work", ".:result_id"]
	for property_path in properties:
		sync_config.add_property(property_path)
		sync_config.property_set_spawn(property_path, false)
		sync_config.property_set_replication_mode(property_path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)

	

# The child station has to call super.process(delta) for this to be called
func process(delta: float) -> void:
	super.process(delta)
	#SweetLogger.debug("station process  result_id: {0}, work: {1}, max_work: {2}", [result_id, current_work, max_work])
	refresh_display()


# Propagate events to clients
@rpc("authority", "call_local", "reliable")
func _everyone_on_work_complete():
	on_work_complete()


## Virutal methods ##
# The child station implements these if it cares about them.
func on_work_complete() -> void:
	SweetLogger.debug("Not implemented in {0}", [name])
	

# The child station has to call super.refresh_display for this to be called
func refresh_display() -> void:
	super.refresh_display()
	var is_active: bool = not result_id.is_empty()
	progress_bar.set_bar_visible(is_active)
	progress_bar.set_progress((current_work / max_work) if is_active else 0.0)


## Public methods ## 
# Will be called by clients to the server, and server to server
func add_work(work: float) -> void:
	SweetLogger.debug("Add work: {0} current: {1} max_work: {2}", [snappedf(work, 0.01), snappedf(current_work, 0.01), snappedf(max_work, 0.01)])
	if work <= 0:
		SweetLogger.warning("Work to add must be positive, work: {0}", [work])
		return
	if not NetworkManager.owns_world():
		server_add_work.rpc_id(1, work)
		return
	if not result_id or result_id.is_empty():
		SweetLogger.warning("Work can not be added when result_id is empty")
		return
	current_work += work
	if current_work >= max_work:
		_everyone_on_work_complete.rpc()


@rpc("any_peer", "call_remote", "reliable")
func server_add_work(work: float) -> void:
	add_work(work)


# Converts the currenly held item into result_id, by despawning it and instantiating a new item
func convert_item() -> Node3D:
	if not NetworkManager.owns_world():
		return
	SweetLogger.info("Convert item, result_id: {0}", [result_id])
	if not NetworkManager.owns_world:
		SweetLogger.warning("Only the server should ever call this!")
		return null
	if not result_id or result_id.is_empty():
		SweetLogger.warning("Station tried to convert item, but result_id is null or empty!")
		return
	var old_pickable = snap_zone.picked_up_object
	if not old_pickable:
		SweetLogger.warning("Station tried to convert item, but item is missing!")
		return null
	var target_id := result_id
	var original_transform = old_pickable.global_transform
	var new_scene_instance = NetworkManager.spawn_item(RecipeManager.get_item_scene(target_id).resource_path, original_transform)

	reset()

	# Drop and free the old item and pick up the new one
	SweetLogger.debug("Freeing old_pickable {0}", [old_pickable])
	snap_zone.drop_object()
	NetworkManager.despawn_item(old_pickable)
	snap_zone.pick_up_object(new_scene_instance)
	SweetLogger.info("Convert item into id: {0}, node name: {1}", [target_id, new_scene_instance.name])
	return new_scene_instance


func reset() -> void:
	SweetLogger.debug("->[]")
	current_work = 0
	max_work = 0
	result_id = ""
