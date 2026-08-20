class_name DayController
extends Node

# DayController Emits singals to spawn customers.

var day_time_remaining: float = 0.0
var customers_spawned: int = 0
var customers_served: int = 0


func _ready() -> void:
	GameManager.set_game_state(GameManager.GameState.BUILDING)
	Signals.game_state_changed.connect(_on_game_state_changed)
	Signals.table_satisfied.connect(_on_table_statisfied)

func _on_game_state_changed(new_state: GameManager.GameState) -> void:
	if new_state == GameManager.GameState.RUNNING:
		start_next_day()
	

func _on_table_statisfied(_table: Table) -> void:
	customers_served += 1
	SweetLogger.info("Spawned: {0} served: {1}, per_day: {2} time_remaining: {3}, progress: {4}", [customers_spawned, customers_served, GameManager.customers_per_day, snappedf(day_time_remaining, 0.1), snappedf(get_day_progression(), 0.1)])


# Returns 0-1 progress of the day time
func get_day_progression() -> float:
	return clampf(1 - (day_time_remaining / GameManager.day_length_seconds), 0.0, 1.0)


func _reset_values() -> void:
	day_time_remaining = GameManager.day_length_seconds
	customers_spawned = 0
	customers_served = 0


func start_next_day() -> void:
	SweetLogger.info("Starting next day")
	_reset_values()
	GameManager.set_customers_per_day(GameManager.customers_per_day + GameManager.customers_count_increase_per_day)
	GameManager.set_day_number(GameManager.day_number + 1)
	
	
func finish_current_day() -> void:
	SweetLogger.info("Finishing current day")
	_reset_values()
	GameManager.set_game_state(GameManager.GameState.BUILDING)


func _process(delta: float) -> void:
	if not NetworkManager.owns_world():
		return
	if GameManager.game_state != GameManager.GameState.RUNNING:
		return
	
	if day_time_remaining > 0:
		day_time_remaining -= delta
		day_time_remaining = max(0, day_time_remaining)

	var customers_at_this_time = GameManager.customers_per_day  * get_day_progression()
	if customers_spawned < customers_at_this_time:
		customers_spawned += 1
		SweetLogger.info("Requesting to spawn customer")
		Signals.request_customer_spawn.emit()
	# If day complete
	if GameManager.customers_per_day == customers_served and customers_spawned == GameManager.customers_per_day:
		SweetLogger.info("Day complete")
		finish_current_day()
