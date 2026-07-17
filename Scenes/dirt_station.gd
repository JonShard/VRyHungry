extends StaticBody3D

@onready var snap_zone: XRToolsSnapZone = $XRToolsSnapZone

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	snap_zone.has_picked_up.connect(_makeDirty)

func _makeDirty(item) -> void:
	var plate: PlateController = item.get_node_or_null("PlateController") as PlateController
	if not plate.is_dirty:
		plate.is_dirty = true
		print("Dirt Station could not find Dirty in: ", item)
	
 
