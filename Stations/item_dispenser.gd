extends StaticBody3D

@export var item_scene : PackedScene
@onready var snap_zone: XRToolsSnapZone = $XRToolsSnapZone

func _ready() -> void:
	if not item_scene:
		SweetLogger.warning("{0} missing item_scene reference", [name])
	if not snap_zone:
		SweetLogger.warning("{0} missing snap_zone reference", [name])


func _process(_delta: float) -> void:
	if not NetworkManager.owns_world():
		return
	#if snap_zone.picked_up_object: # Player picked up this station
		#if visible:
			#snap_zone.picked_up_object.enabled = true
		#else:
			#snap_zone.picked_up_object.enabled = false
		#return
		#
	if not snap_zone.picked_up_object:
		SweetLogger.debug("Missing item, spawning new item")
		var new_item = NetworkManager.spawn_item(item_scene.resource_path, snap_zone.global_transform)
		snap_zone.pick_up_object(new_item)
