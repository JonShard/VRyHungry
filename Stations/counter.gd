extends StaticBody3D

@export var chop_work_steps: float = 5.0

@export var audio: AudioStreamPlayer3D
@export var chop_audio: AudioStream
@export var knife: XRToolsPickable
@onready var snap_zone: XRToolsSnapZone = $XRToolsSnapZone
@export var progress_bar: ProgressBar3D

# Chopping state. Follow the hob/sink pattern so the display refreshes when
# values change; only the world owner runs the station's process in practice.
var process_result: String = "": set = _set_result
var process_result_work: float = 0.0: set = _set_result_work
var work_progress: float = 0.0: set = _set_work_progress


func _ready() -> void:
	if not audio:
		push_error("Counter is missing reference to AudioStreamPlayer3D")
	if not chop_audio:
		push_error("Counter is missing reference to chop_audio AudioStream")
	if not progress_bar or progress_bar is not ProgressBar3D:
		push_error("Counter missing reference to progressbar, or wrong type:", progress_bar)
	if not knife or knife is not XRToolsPickable:
		push_error("Counter missing reference to knife, or wrong type:", knife)
	if not snap_zone or snap_zone is not XRToolsSnapZone:
		push_error("Counter missing reference to snap_zone, or wrong type:", snap_zone)

	snap_zone.has_picked_up.connect(_on_object_picked_up)
	snap_zone.has_dropped.connect(_on_object_dropped)
	progress_bar.override_fill_color(Color.GREEN)
	_hide_all_tools()
	_refresh_progress_bar()


func _set_work_progress(value: float) -> void:
	work_progress = value
	_refresh_progress_bar()


func _set_result(value: String) -> void:
	process_result = value
	_refresh_progress_bar()
	# When a chopping recipe is set, show the knife for the player to use.
	if not process_result.is_empty():
		knife.visible = true
		knife.enabled = true
		print("Counter: chopping recipe set: ", process_result)
	else:
		_hide_all_tools()


func _set_result_work(value: float) -> void:
	process_result_work = value
	_refresh_progress_bar()


func _refresh_progress_bar() -> void:
	if not progress_bar:
		return
	var progress := 0.0
	if process_result != "" and process_result_work > 0:
		progress = clampf(float(work_progress) / process_result_work, 0.0, 1.0)

	progress_bar.set_progress(progress)
	progress_bar.set_bar_visible(not process_result.is_empty())
	progress_bar.override_fill_color(Color.GREEN)


# Add work from gesture area (knife hits). This increments the chopping progress.
func add_work(work: float) -> void:
	print("Counter add_work: ", work)
	# Only the world owner should drive the authoritative state. Guarding is
	# handled by higher-level NetworkManager logic elsewhere, mirror hob's
	# convert_held_to_item which checks ownership before spawning.
	work_progress += work
	# Play chopping sound if available
	if audio and chop_audio:
		audio.stream = chop_audio
		audio.play()
	# If we've reached the required time, convert the held item
	if process_result != "" and process_result_work > 0 and work_progress >= process_result_work:
		print("Counter: chopping complete, converting item to: ", process_result)
		work_progress = 0
		convert_held_to_item(process_result)


func _on_gesture_area_body_entered(body: Node3D) -> void:
	print("Counter: gesture area entered: ", body)
	if body.is_in_group("chopping_tool"):
		if process_result == "":
			print("Counter: knife entered but nothing to chop")
			return
		add_work(chop_work_steps)


func _on_object_picked_up(_item: Variant) -> void:
	print("Counter: object picked up: ", _item)
	var food_item = Helper.find_food_item(_item)
	if not food_item:
		print("Counter: held object is not a FoodItem")
		return
	
	var result = RecipeManager.get_chopping_result(food_item.id)
	if not result:
		print("Counter: held a FoodItem that is not choppable, id: %s  process_result: %s" % [food_item.id, result])
		return

	process_result = result
	process_result_work = RecipeManager.get_chopping_work(food_item.id)
	print("Counter: set process_result ", process_result, " work: ", process_result_work)


func _on_object_dropped(_item: Variant) -> void:
	print("Counter: object drop ")
	work_progress = 0
	process_result = ""
	process_result_work = 0
	_hide_all_tools()


func convert_held_to_item(_item: String) -> void:
	if not NetworkManager.owns_world():
		return
	print("Counter converting ", _item)

	var old_pickable = snap_zone.picked_up_object
	if not old_pickable:
		push_warning("Counter finished processing _item, but snap zone is missing its reference")
		return

	var original_transform = old_pickable.global_transform
	var new_scene_instance = NetworkManager.spawn_item(RecipeManager.get_item_scene(_item).resource_path, original_transform)

	print("Counter freeing old_pickable  ", old_pickable)
	snap_zone.drop_object()
	NetworkManager.despawn_item(old_pickable)
	snap_zone.pick_up_object(new_scene_instance)


func _hide_all_tools():
	knife.visible = false
	knife.enabled = false
