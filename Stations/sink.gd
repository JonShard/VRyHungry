extends StaticBody3D

const plate_wash_time: float = 3.0
@export_range(0.0, 10.0, 0.1) var wash_speed: float = 1.0

@onready var snap_zone: XRToolsSnapZone = $XRToolsSnapZone
@onready var progress_bar: ProgressBar3D = $ProgressBar3D

var time_washed: float = 0.0
var is_washing: bool = false
var plate: PlateController = null

func _ready() -> void:
	if not progress_bar or progress_bar is not ProgressBar3D:
		push_error("Sink missing reference to progressbar, or wrong type:", progress_bar)

	snap_zone.has_picked_up.connect(_on_object_picked_up)
	snap_zone.has_dropped.connect(_on_object_dropped)
	progress_bar.override_fill_color(Color.DODGER_BLUE)
	_refresh_progress_bar()
 

func _refresh_progress_bar() -> void:
	progress_bar.set_progress(clampf(float(time_washed) / plate_wash_time, 0.0, 1.0))
	progress_bar.set_bar_visible(is_washing)


func _on_object_picked_up(_item) -> void:
	print("Sink: object picked up: ", _item)
	plate = _item.get_node_or_null("PlateController") as PlateController
	if plate:
		is_washing = plate.is_dirty


func _on_object_dropped() -> void:
	print("Sink: object drop ")
	_reset_sink()


func _reset_sink():
	time_washed = 0
	is_washing = false
	plate = null
	_refresh_progress_bar()

func complete_washing():
		plate.is_dirty = false
		_reset_sink()
		print("Sink washing complete!")


func _process(delta: float) -> void:
	if is_washing:
		time_washed += wash_speed * delta
		_refresh_progress_bar()
		print("Sink washing plate: ", time_washed)

	if time_washed >= plate_wash_time:
		complete_washing()
