extends StaticBody3D


@export var cook_speed = 1
@onready var snap_zone: XRToolsSnapZone = $XRToolsSnapZone
@onready var progress_bar: ProgressBar3D = $ProgressBar3D

## Cooking state. All three are replicated (see Hob.tscn's Sync node) and each
## refreshes the display when it changes, which is what makes the hob look alive
## on a client: only the world owner runs the station's _process and its snap
## zone, so a client never reaches the code below by itself and would otherwise
## show a hob that never lights up.
@export var time_cooked: float = 0.0: set = _set_time_cooked
@export var cooking_result: String = "": set = _set_cooking_result
@export var cooking_result_time: float = 0.0: set = _set_cooking_result_time


func _set_time_cooked(value: float) -> void:
	if is_equal_approx(time_cooked, value):
		return
	time_cooked = value
	_refresh_display()


func _set_cooking_result(value: String) -> void:
	if cooking_result == value:
		return
	cooking_result = value
	_refresh_display()
	# The flames follow whether we're cooking, on every peer.
	_play_animation("hob" if not cooking_result.is_empty() else "RESET")


func _set_cooking_result_time(value: float) -> void:
	if is_equal_approx(cooking_result_time, value):
		return
	cooking_result_time = value
	_refresh_display()


func _ready() -> void:
	if not progress_bar or progress_bar is not ProgressBar3D:
		push_error("Hob missing reference to progressbar, or wrong type:", progress_bar)
	snap_zone.has_picked_up.connect(_on_object_picked_up)
	snap_zone.has_dropped.connect(_on_object_dropped)
	_refresh_display()


func _play_animation(name: String) -> void:
	# Replicated setters can fire before the node is in the tree (spawn payload),
	# when the @onready children don't exist yet.
	var player := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player:
		player.play(name)


func _refresh_display() -> void:
	# Guarded for the same reason as _play_animation.
	if not progress_bar:
		return
	var progress := 0.0
	if cooking_result and cooking_result_time > 0:
		progress = clampf(float(time_cooked) / cooking_result_time, 0.0, 1.0)

	progress_bar.set_progress(progress)
	progress_bar.set_bar_visible(not cooking_result.is_empty())
	progress_bar.override_fill_color(Color.RED if cooking_result == "charcoal" else Color.GREEN)

func _on_object_picked_up(_item) -> void:
	SweetLogger.debug("object picked up: {0}", [_item], "hob.gd", "_on_object_picked_up")

	# Find the CookableItem in held object
	var _food_item = _item.get_node_or_null("FoodItem") as FoodItem
	if not _food_item:
		SweetLogger.debug("held object is not a FoodItem", [], "hob.gd", "_on_object_picked_up")
		return
	var result = RecipeManager.get_cooking_result(_food_item.id)
	if not result:
		SweetLogger.debug("held a FoodItem that is not cookable, id: {0} result: {1}", [_food_item.id, result], "hob.gd", "_on_object_picked_up")
		return

	cooking_result = result
	cooking_result_time = RecipeManager.get_cooking_time(_food_item.id)
	SweetLogger.debug("set cooking_result {0}", [cooking_result], "hob.gd", "_on_object_picked_up")
	# The setters above already refresh the display and start the flames.


func _on_object_dropped(_item) -> void:
	SweetLogger.debug("object drop", [], "hob.gd", "_on_object_dropped")
	time_cooked = 0
	cooking_result = ""
	cooking_result_time = 0


func convert_held_to_item(_item: String) -> void:
	if not NetworkManager.owns_world():
		return
	SweetLogger.debug("converting {0}", [_item], "hob.gd", "convert_held_to_item")

	var old_pickable = snap_zone.picked_up_object
	if not old_pickable:
		push_warning("Hob finished cooking _item, but snap zone is missing its reference")
		return

	# Spawn the new item through the server so it replicates to every peer
	# (including late joiners), in the old item's position.
	var original_transform = old_pickable.global_transform
	var new_scene_instance = NetworkManager.spawn_item(RecipeManager.get_item_scene(_item).resource_path, original_transform)

	# Drop and free the old item and pick up the new one
	SweetLogger.debug("freeing old_pickable {0}", [old_pickable], "hob.gd", "convert_held_to_item")
	snap_zone.drop_object()
	NetworkManager.despawn_item(old_pickable)
	snap_zone.pick_up_object(new_scene_instance)


# If cooking something, progress cooking, when done, convert item
func _process(delta: float) -> void:
	if cooking_result:
		#print("Hob cooking_result: ", cooking_result)
		time_cooked += cook_speed * delta		
		_refresh_display()
		if time_cooked >= cooking_result_time:
			time_cooked = 0
			convert_held_to_item(cooking_result)

		
