class_name Sink
extends WorkStation

const plate_wash_time: float = 3.0
@export_range(0.0, 10.0, 0.1) var wash_speed: float = 1.0

var plate: PlateController = null


func _ready() -> void:
	super.ready()
	SweetLogger.debug("Sink {0} _ready", [name])


func _start_washing(work: float) -> void:
	if not enabled:
		return
	result_id = "clean"
	max_work = work
	SweetLogger.info("Start washing - max_work: {0}", [max_work])

func _set_effects_playing(is_playing: bool) -> void:
	SweetLogger.debug("Set Sink effects: {0}", [is_playing])
	var player := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player:
		player.play("working" if is_playing else "RESET")
	for effect in ["water", "bubbles", "GPUParticles3D"]:
		var node := get_node_or_null(effect) as Node3D
		if node:
			node.visible = is_playing


func _process(delta: float) -> void:
	super.process(delta)
	if not enabled:
		return
	if result_id:
		add_work(wash_speed * delta)


# Called from Station base class
func refresh_display() -> void:
	super.refresh_display()
	progress_bar.override_fill_color(Color.DODGER_BLUE)


# Called from Station base class
func on_object_picked_up(item: Node3D) -> void:
	plate = item.get_node_or_null("PlateController") as PlateController
	if not plate or not plate.is_dirty:
		return
	_set_effects_playing(true)
	_start_washing(plate_wash_time)


# Called from Station base class
func on_object_dropped(_item: Node3D) -> void:
	SweetLogger.debug("->[]")
	_set_effects_playing(false)
	plate = null
	reset()


# Called from Station base class
func on_work_complete():
	SweetLogger.debug("->[]")
	_set_effects_playing(false)
	plate.is_dirty = false
	reset()


