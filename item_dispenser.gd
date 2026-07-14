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
	if not snap_zone.picked_up_object:
		var new_item = item_scene.instantiate()
		
		# Add the new item to the hob's parent (so it lives in the main world space)
		get_parent().add_child(new_item)
		new_item.global_transform = snap_zone.transform
		snap_zone.pick_up_object(new_item)
