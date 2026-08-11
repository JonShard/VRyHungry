extends StaticBody3D

const plate_wash_time: float = 3.0
@export_range(0.0, 10.0, 0.1) var wash_speed: float = 1.0

@onready var snap_zone: XRToolsSnapZone = $XRToolsSnapZone
@onready var progress_bar: ProgressBar3D = $ProgressBar3D

## Washing state. Both are replicated (see sink.tscn's Sync node) and refresh the
## display when they change. Only the world owner runs this station's _process
## and snap zone, so without this a client never updates its bar — it stayed
## frozen on screen long after the plate came out clean.
@export var time_washed: float = 0.0: set = _set_time_washed
@export var is_washing: bool = false: set = _set_is_washing
@export var plate: PlateController = null


func _set_time_washed(value: float) -> void:
	if is_equal_approx(time_washed, value):
		return
	time_washed = value
	_refresh_progress_bar()


func _set_is_washing(value: bool) -> void:
	if is_washing == value:
		return
	is_washing = value
	_refresh_progress_bar()
	_set_effects_playing(is_washing)


# Water, bubbles and the animation follow the washing state on every peer, not
# just the one running the logic.
func _set_effects_playing(playing: bool) -> void:
	var player := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player:
		player.play("working" if playing else "RESET")
	for effect in ["water", "bubbles", "GPUParticles3D"]:
		var node := get_node_or_null(effect) as Node3D
		if node:
			node.visible = playing

func _ready() -> void:
	if not progress_bar or progress_bar is not ProgressBar3D:
		push_error("Sink missing reference to progressbar, or wrong type:", progress_bar)

	snap_zone.has_picked_up.connect(_on_object_picked_up)
	snap_zone.has_dropped.connect(_on_object_dropped)
	progress_bar.override_fill_color(Color.DODGER_BLUE)
	_refresh_progress_bar()
 

func _refresh_progress_bar() -> void:
	if not progress_bar:
		return
	progress_bar.set_progress(clampf(float(time_washed) / plate_wash_time, 0.0, 1.0))
	progress_bar.set_bar_visible(is_washing)


func _on_object_picked_up(_item) -> void:
	SweetLogger.debug("object picked up: {0}", [_item])
	plate = _item.get_node_or_null("PlateController") as PlateController
	if plate:
		# The setter starts the effects and shows the bar, here and on clients.
		is_washing = plate.is_dirty


func _on_object_dropped(_item) -> void:
	SweetLogger.debug("object drop")
	_reset_sink()


func _reset_sink():
	time_washed = 0
	is_washing = false
	plate = null

func complete_washing():
		if not plate:
			return
		plate.is_dirty = false
		_reset_sink()
		SweetLogger.debug("washing complete!")


func _process(delta: float) -> void:
	if is_washing:
		time_washed += wash_speed * delta
		_refresh_progress_bar()
		SweetLogger.debug("washing plate: {0}", [time_washed])

	if time_washed >= plate_wash_time:
		complete_washing()
