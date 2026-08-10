class_name DayController
extends Node

# DayController Emits singals to spawn customers.

var day_time_remaining: float = 0.0
var customers_spawned: int = 0
var customers_served: int = 0


func _ready() -> void:
	GameManager.set_game_state(GameManager.GameState.BUILDING)
	Signals.game_state_changed.connect(_on_game_state_changed)


func _on_game_state_changed(new_state: GameManager.GameState) -> void:
	if new_state == GameManager.GameState.RUNNING:
		start_next_day()
	

# Returns 0-1 progress of the day time
func get_day_progression() -> float:
	return 1 - (day_time_remaining / GameManager.day_length_seconds)


func _reset_values() -> void:
	day_time_remaining = GameManager.day_length_seconds
	customers_spawned = 0
	customers_served = 0


func start_next_day() -> void:
	SweetLogger.info("starting next day", [], "day_controller.gd", "start_next_day")
	_reset_values()
	GameManager.set_customers_per_day(GameManager.customers_per_day + GameManager.customers_count_increase_per_day)
	GameManager.set_day_number(GameManager.day_number + 1)
	
	
func finish_current_day() -> void:
	SweetLogger.info("finishing current day", [], "day_controller.gd", "finish_current_day")
	_reset_values()


func _process(delta: float) -> void:
	if GameManager.game_state != GameManager.GameState.RUNNING:
		return
		
	day_time_remaining -= delta
	var customers_at_this_time = GameManager.customers_per_day  * get_day_progression()
	#print("DayController: customers_at_this_time: ", customers_at_this_time)
	if customers_spawned < customers_at_this_time:
		customers_spawned += 1
		SweetLogger.debug("spawning customer", [], "day_controller.gd", "_process")
		Signals.request_customer_spawn.emit()
	# If day complete
	if GameManager.customers_per_day == customers_served and customers_spawned == GameManager.customers_per_day:
		SweetLogger.info("day complete", [], "day_controller.gd", "_process")
		finish_current_day()
