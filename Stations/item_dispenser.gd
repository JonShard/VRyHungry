extends StaticBody3D

@export var item_scene : PackedScene
@onready var snap_zone: XRToolsSnapZone = $XRToolsSnapZone

func _ready() -> void:
	if not item_scene:
		push_error("Item dispenser is missing a reference to it's item to dispense")
	if not snap_zone:
		push_error("Item dispenser is missing a reference to its snap zone child")


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
		SweetLogger.debug("missing item, spawning new item")
		var new_item = NetworkManager.spawn_item(item_scene.resource_path, snap_zone.global_transform)
		snap_zone.pick_up_object(new_item)
