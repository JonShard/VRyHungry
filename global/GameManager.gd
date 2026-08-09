extends Node

const STAR_DAY_FREQUENCY: int = 3 

var money: int = 1000:
	get:
		return money
	set(value):
		if not multiplayer.is_server():
			push_warning("Clients cannot modify money directly.")
			return
		money = max(0, value)
		_sync_money.rpc(money)

@rpc("authority", "call_remote", "reliable") # Server updates clients
func _sync_money(new_amount: int) -> void:
	money = new_amount


var day_number: int = 1:
	get:
		return day_number
	set(value):
		if not multiplayer.is_server():
			push_warning("Clients cannot modify day_number directly.")
			return
		day_number = value
		_sync_day_number.rpc(day_number)

@rpc("authority", "call_remote", "reliable")
func _sync_day_number(new_value: int) -> void:
	day_number = new_value


var meals_in_play: Array[String] = []:
	get:
		return meals_in_play
	set(value):
		if not multiplayer.is_server():
			push_warning("Clients cannot modify meals_in_play directly.")
			return
		meals_in_play = value
		_sync_meals_in_play.rpc(meals_in_play)

@rpc("authority", "call_remote", "reliable")
func _sync_meals_in_play(new_value: Array[String]) -> void:
	meals_in_play = new_value


var sides_in_play: Array[String] = []:
	get:
		return sides_in_play
	set(value):
		if not multiplayer.is_server():
			push_warning("Clients cannot modify sides_in_play directly.")
			return
		sides_in_play = value
		_sync_sides_in_play.rpc(sides_in_play)

@rpc("authority", "call_remote", "reliable")
func _sync_sides_in_play(new_value: Array[String]) -> void:
	sides_in_play = new_value


# GameConfig - difficulty settings
var day_length_seconds: float = 60.0:
	get:
		return day_length_seconds
	set(value):
		if not multiplayer.is_server():
			push_warning("Clients cannot modify day_length_seconds directly.")
			return
		day_length_seconds = value
		_sync_day_length_seconds.rpc(day_length_seconds)

@rpc("authority", "call_remote", "reliable")
func _sync_day_length_seconds(new_value: float) -> void:
	day_length_seconds = new_value


var customers_per_day: float = 5.0:
	get:
		return customers_per_day
	set(value):
		if not multiplayer.is_server():
			push_warning("Clients cannot modify customers_per_day directly.")
			return
		customers_per_day = value
		_sync_customers_per_day.rpc(customers_per_day)

@rpc("authority", "call_remote", "reliable")
func _sync_customers_per_day(new_value: float) -> void:
	customers_per_day = new_value


var customers_count_increase_per_day: float = 1.0:
	get:
		return customers_count_increase_per_day
	set(value):
		if not multiplayer.is_server():
			push_warning("Clients cannot modify customers_count_increase_per_day directly.")
			return
		customers_count_increase_per_day = value
		_sync_customers_count_increase_per_day.rpc(customers_count_increase_per_day)

@rpc("authority", "call_remote", "reliable")
func _sync_customers_count_increase_per_day(new_value: float) -> void:
	customers_count_increase_per_day = new_value


var group_min_size: int = 1:
	get:
		return group_min_size
	set(value):
		if not multiplayer.is_server():
			push_warning("Clients cannot modify group_min_size directly.")
			return
		group_min_size = value
		_sync_group_min_size.rpc(group_min_size)

@rpc("authority", "call_remote", "reliable")
func _sync_group_min_size(new_value: int) -> void:
	group_min_size = new_value


var group_max_size: int = 2:
	get:
		return group_max_size
	set(value):
		if not multiplayer.is_server():
			push_warning("Clients cannot modify group_max_size directly.")
			return
		group_max_size = value
		_sync_group_max_size.rpc(group_max_size)

@rpc("authority", "call_remote", "reliable")
func _sync_group_max_size(new_value: int) -> void:
	group_max_size = new_value



enum GameState {
	RUNNING,
	GAME_OVER,
	BUILDING
}

var game_state: GameState = GameState.BUILDING:
	get:
		return game_state
	set(value):
		if not multiplayer.is_server():
			push_warning("Clients cannot modify game_state directly.")
			return
		game_state = value
		_sync_game_state.rpc(game_state)
		Signals.game_state_changed.emit(game_state)

@rpc("authority", "call_remote", "reliable")
func _sync_game_state(new_value: GameState) -> void:
	game_state = new_value
	Signals.game_state_changed.emit(game_state)


func get_random_meal() -> String:
	if meals_in_play.size() == 0:
		push_error("GameManager: get_random_meal() called but meals_in_play is empty")
		return ""
	var rand_index = randi() % meals_in_play.size()
	print("GameManager: get_random_meal() returning ", meals_in_play[rand_index])
	return meals_in_play[rand_index]


func get_random_side() -> String:
	print("GameManager: get_random_side() ")
	if sides_in_play.size() == 0:
		push_error("GameManager: get_random_side() called but sides_in_play is empty")
		return ""
	var rand_index = randi() % sides_in_play.size()
	print("GameManager: get_random_side() list=%s returning %s" % [sides_in_play, sides_in_play[rand_index]])
	return sides_in_play[rand_index]


func _restart():
	print("restart Game")
	game_state = GameState.RUNNING


func game_over():
	print("Game Over")
	game_state = GameState.GAME_OVER
	Signals.game_over.emit()
