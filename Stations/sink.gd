extends StaticBody3D

const plate_wash_time: float = 3.0
@export var plate_scene : PackedScene
@export_range(0.0, 10.0, 0.1) var wash_speed: float = 1.0

@onready var snap_zone: XRToolsSnapZone = $XRToolsSnapZone

var progress: float = 0.0

func _ready() -> void:
	if not plate_scene:
		push_error("Sink is missing reference to plate scene")

func _process(delta: float) -> void:
	var item = snap_zone.picked_up_object
	
	if not item:
		progress = 0
		return # Exit early since there's nothing to process

	
	var plate: PlateController = item.get_node_or_null("PlateController") as PlateController
	if plate:
		# Not dirty? Nothing to wash
		if not plate.is_dirty:
			return
			
		# Washing logic using the encapsulated property
		if progress >= plate_wash_time:
			plate.is_dirty = false # This automatically updates visibility and the container state!
			print("Sink washing complete!")
		else:
			progress += wash_speed * delta
			print("Sink washing plate: ", progress)
		
	# Sink empty, reset progress
	if not snap_zone.picked_up_object:
		progress = 0
	
