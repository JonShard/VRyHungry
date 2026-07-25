extends StaticBody3D

@export var item_scene : PackedScene
@onready var snap_zone: XRToolsSnapZone = $XRToolsSnapZone

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if not item_scene:
		push_error("Item dispenser is missing a reference to it's item to dispense")
	if not snap_zone:
		push_error("Item dispenser is missing a reference to its snap zone child")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if not NetworkManager.owns_world():
		return
	if not snap_zone.picked_up_object:
		var new_item = NetworkManager.spawn_item(item_scene.resource_path, snap_zone.global_transform)
		snap_zone.pick_up_object(new_item)
