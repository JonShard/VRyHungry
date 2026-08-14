class_name ItemDispenser
extends Station

@export var item_scene: PackedScene


func _ready() -> void:
	super.ready()
	SweetLogger.debug("ItemDispenser {0} _ready", [name])
	if not item_scene:
		SweetLogger.warning("{0} missing item_scene reference", [name])


func _process(delta: float) -> void:
	super.process(delta)
	if not NetworkManager.owns_world():
		return
	if not enabled:
		if snap_zone.picked_up_object:
			var item := snap_zone.picked_up_object
			snap_zone.drop_object()
			NetworkManager.despawn_item(item)
		return
	if not snap_zone.picked_up_object:
		SweetLogger.debug("Missing item, spawning new item")
		var new_item = NetworkManager.spawn_item(item_scene.resource_path, snap_zone.global_transform)
		snap_zone.pick_up_object(new_item)
