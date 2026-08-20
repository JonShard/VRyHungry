class_name Counter
extends WorkStation

@export var chop_work_steps: float = 5.0
@export var chop_min_speed: float = 2.0

@export var audio: AudioStreamPlayer3D
@export var chop_audio: AudioStream
@export var knife: XRToolsPickable


func _ready() -> void:
	super.ready()
	SweetLogger.debug("Counter {0} _ready", [name])
	Helper.check_reference(self, audio, AudioStreamPlayer3D)
	Helper.check_reference(self, chop_audio, AudioStream)
	Helper.check_reference(self, knife, XRToolsPickable)
	_disable_all_tools()


func _start_chopping(id: String, work: float) -> void:
	if not enabled:
		return
	result_id = id
	max_work = work
	SweetLogger.info("Start chopping - result_id: {0}, max_work: {1}", [result_id, max_work])


func _process(delta: float) -> void:
	super.process(delta)


func _enable_tool(_item: XRToolsPickable):
	SweetLogger.debug("Enable tool {0} on {1}", [_item.name, name])
	_item.visible = true
	_item.get_node("NetPickable").grabbable = true


func _disable_tool(_item: XRToolsPickable):
	SweetLogger.debug("Disable tool {0} on {1}", [_item.name, name])
	_item.visible = false
	_item.get_node("NetPickable").grabbable = false

func _disable_all_tools():
	SweetLogger.debug("Disable all tools on {0}", [name])
	_disable_tool(knife)


func _on_gesture_area_body_entered(body: Node3D) -> void:
	SweetLogger.debug("Gesture area entered: {0}", [body])
	if not body.is_in_group("chopping_tool"):
		return
	if result_id == "":
		SweetLogger.debug("Knife entered but nothing to chop")
		return

	var speed := 0.0
	if body is RigidBody3D:
		speed = body.linear_velocity.length()
	elif body is CharacterBody3D:
		speed = body.velocity.length()

	if speed < chop_min_speed:
		SweetLogger.debug("Knife too slow for chopping: {0}", [speed])
		return

	if audio and chop_audio:
		audio.stream = chop_audio
		audio.play()

	add_work(chop_work_steps)


# Called from Station base class
func refresh_display() -> void:
	super.refresh_display()
	progress_bar.override_fill_color(Color.GREEN)


# Called from Station base class
func on_food_item_picked_up(food_item: FoodItem) -> void:
	SweetLogger.debug("Object picked up: {0}", [food_item])

	if not food_item:
		SweetLogger.debug("Held object is not a FoodItem")
		return
	var result = RecipeManager.get_chopping_result(food_item.id)
	if not result:
		SweetLogger.debug("Held a FoodItem that is not choppable, id: {0} result: {1}", [food_item.id, result])
		return

	_enable_tool(knife)
	_start_chopping(result, RecipeManager.get_chopping_work(food_item.id))


# Called from Station base class
func on_object_dropped(_item: Node3D) -> void:
	SweetLogger.debug("->[]")
	_disable_all_tools()
	reset()


# Called from Station base class
func on_work_complete():
	SweetLogger.debug("->[]")
	_disable_all_tools()
	convert_item()
