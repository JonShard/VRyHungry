class_name Hob
extends WorkStation

@export var cook_speed = 1

@export	var animation_player: AnimationPlayer


func _ready() -> void:
	super.ready()
	SweetLogger.debug("Hob {0} _ready", [name])
	if not animation_player:
		SweetLogger.warning("{0} missing animation_player reference", [name])
	
func _start_cooking(id: String, work: float) -> void:
	animation_player.play("hob")
	if not enabled:
		return	
	
	result_id = id
	max_work = work
	SweetLogger.info("Start cooking - result_id: {0}, max_work: {1}", [result_id, max_work])
	# The flames follow whether we're cooking, on every peer.


func _process(delta: float) -> void:
	super.process(delta)
	if not enabled:
		return
	if result_id:
		add_work(cook_speed * delta)


# Called from Station base class
func refresh_display() -> void:
	super.refresh_display()
	progress_bar.override_fill_color(Color.RED if result_id == "charcoal" else Color.GREEN)


# Called from Station base class
func on_food_item_picked_up(food_item: FoodItem) -> void:
	SweetLogger.debug("Object picked up: {0}", [food_item])

	if not food_item:
		SweetLogger.debug("Held object is not a FoodItem")
		return
	var result = RecipeManager.get_cooking_result(food_item.id)
	if not result:
		SweetLogger.debug("Held a FoodItem that is not cookable, id: {0} result: {1}", [food_item.id, result])
		return

	_start_cooking(result, RecipeManager.get_cooking_time(food_item.id))


# Called from Station base class
func on_food_item_dropped(_food_item: FoodItem):
	SweetLogger.debug("->[]")
	animation_player.play("RESET")
	reset()


# Called from Station base class
func on_work_complete():
	SweetLogger.debug("->[]")
	animation_player.play("RESET")
	convert_item()
