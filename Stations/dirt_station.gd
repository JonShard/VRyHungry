class_name DirtStation
extends Station


func _ready() -> void:
	super.ready()
	SweetLogger.debug("DirtStation {0} _ready", [name])


# Called from Station base class
func on_object_picked_up(item: Node3D) -> void:
	if not NetworkManager.owns_world():
		return
	var plate: PlateController = item.get_node_or_null("PlateController") as PlateController
	if not plate:
		SweetLogger.debug("Held object is not a Plate")
		return
	if not plate.is_dirty:
		plate.is_dirty = true
