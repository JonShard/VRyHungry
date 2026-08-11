extends StaticBody3D

@onready var snap_zone: XRToolsSnapZone = $XRToolsSnapZone

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	snap_zone.has_picked_up.connect(_makeDirty)

func _makeDirty(item) -> void:
	if not NetworkManager.owns_world():
		return
	var plate: PlateController = item.get_node_or_null("PlateController") as PlateController
	if not plate:
		SweetLogger.debug("held object is not a Plate", [])
		return
	if not plate.is_dirty:
		plate.is_dirty = true
	
 
