extends Node

const STAR_DAY_FREQUENCY: int = 3 

var money: int = 1000: 
	get: return money
		
func set_money(value):
	if multiplayer.is_server():
		money =  max(0,value)
		client_sync_money.rpc(money)
		SweetLogger.info("Set to {0}", [money])
	else:
		SweetLogger.info("Client (peer {0}) attempted direct set, forwarding to server", [multiplayer.get_unique_id()])
		server_set_money.rpc_id(1, value)

@rpc("any_peer", "call_remote", "reliable")  # CLIENT -> SERVER: Request a change
func server_set_money(value: int) -> void: set_money(value)

@rpc("authority", "call_remote", "reliable") # SERVER -> CLIENTS: Replicate new change
func client_sync_money(value: int) -> void: money = value


var day_number: int = 1:
	get:
		return day_number

func set_day_number(value: int) -> void:
	if multiplayer.is_server():
		day_number = value
		client_sync_day_number.rpc(day_number)
		SweetLogger.info("Set to {0}", [day_number])
	else:
		SweetLogger.info("Client (peer {0}) attempted direct set, forwarding to server", [multiplayer.get_unique_id()])
		server_set_day_number.rpc_id(1, value)

@rpc("any_peer", "call_remote", "reliable")
func server_set_day_number(value: int) -> void:
	set_day_number(value)

@rpc("authority", "call_remote", "reliable")
func client_sync_day_number(value: int) -> void:
	day_number = value


var meals_in_play: Array[String] = []:
	get:
		return meals_in_play

func set_meals_in_play(value: Array[String]) -> void:
	if multiplayer.is_server():
		meals_in_play = value
		client_sync_meals_in_play.rpc(meals_in_play)
		SweetLogger.info("Set to {0}", [meals_in_play])
	else:
		SweetLogger.info("Client (peer {0}) attempted direct set, forwarding to server", [multiplayer.get_unique_id()])
		server_set_meals_in_play.rpc_id(1, value)

@rpc("any_peer", "call_remote", "reliable")
func server_set_meals_in_play(value: Array[String]) -> void:
	set_meals_in_play(value)

@rpc("authority", "call_remote", "reliable")
func client_sync_meals_in_play(value: Array[String]) -> void:
	meals_in_play = value


var sides_in_play: Array[String] = []:
	get:
		return sides_in_play

func set_sides_in_play(value: Array[String]) -> void:
	if multiplayer.is_server():
		sides_in_play = value
		client_sync_sides_in_play.rpc(sides_in_play)
		SweetLogger.info("Set to {0}", [sides_in_play])
	else:
		SweetLogger.info("Client (peer {0}) attempted direct set, forwarding to server", [multiplayer.get_unique_id()])
		server_set_sides_in_play.rpc_id(1, value)

@rpc("any_peer", "call_remote", "reliable")
func server_set_sides_in_play(value: Array[String]) -> void:
	set_sides_in_play(value)

@rpc("authority", "call_remote", "reliable")
func client_sync_sides_in_play(value: Array[String]) -> void:
	sides_in_play = value


# GameConfig - difficulty settings
var day_length_seconds: float = 60.0:
	get:
		return day_length_seconds

func set_day_length_seconds(value: float) -> void:
	if multiplayer.is_server():
		day_length_seconds = value
		client_sync_day_length_seconds.rpc(day_length_seconds)
		SweetLogger.info("Set to {0}", [day_length_seconds])
	else:
		SweetLogger.info("Client (peer {0}) attempted direct set, forwarding to server", [multiplayer.get_unique_id()])
		server_set_day_length_seconds.rpc_id(1, value)

@rpc("any_peer", "call_remote", "reliable")
func server_set_day_length_seconds(value: float) -> void:
	set_day_length_seconds(value)

@rpc("authority", "call_remote", "reliable")
func client_sync_day_length_seconds(value: float) -> void:
	day_length_seconds = value


var customers_per_day: float = 5.0:
	get:
		return customers_per_day

func set_customers_per_day(value: float) -> void:
	if multiplayer.is_server():
		customers_per_day = value
		client_sync_customers_per_day.rpc(customers_per_day)
		SweetLogger.info("Set to {0}", [customers_per_day])
	else:
		SweetLogger.info("Client (peer {0}) attempted direct set, forwarding to server", [multiplayer.get_unique_id()])
		server_set_customers_per_day.rpc_id(1, value)

@rpc("any_peer", "call_remote", "reliable")
func server_set_customers_per_day(value: float) -> void:
	set_customers_per_day(value)

@rpc("authority", "call_remote", "reliable")
func client_sync_customers_per_day(value: float) -> void:
	customers_per_day = value


var customers_count_increase_per_day: float = 1.0:
	get:
		return customers_count_increase_per_day

func set_customers_count_increase_per_day(value: float) -> void:
	if multiplayer.is_server():
		customers_count_increase_per_day = value
		client_sync_customers_count_increase_per_day.rpc(customers_count_increase_per_day)
		SweetLogger.info("Set to {0}", [customers_count_increase_per_day])
	else:
		SweetLogger.info("Client (peer {0}) attempted direct set, forwarding to server", [multiplayer.get_unique_id()])
		server_set_customers_count_increase_per_day.rpc_id(1, value)

@rpc("any_peer", "call_remote", "reliable")
func server_set_customers_count_increase_per_day(value: float) -> void:
	set_customers_count_increase_per_day(value)

@rpc("authority", "call_remote", "reliable")
func client_sync_customers_count_increase_per_day(value: float) -> void:
	customers_count_increase_per_day = value


var group_min_size: int = 1:
	get:
		return group_min_size

func set_group_min_size(value: int) -> void:
	if multiplayer.is_server():
		group_min_size = value
		client_sync_group_min_size.rpc(group_min_size)
		SweetLogger.info("Set to {0}", [group_min_size])
	else:
		SweetLogger.info("Client (peer {0}) attempted direct set, forwarding to server", [multiplayer.get_unique_id()])
		server_set_group_min_size.rpc_id(1, value)

@rpc("any_peer", "call_remote", "reliable")
func server_set_group_min_size(value: int) -> void:
	set_group_min_size(value)

@rpc("authority", "call_remote", "reliable")
func client_sync_group_min_size(value: int) -> void:
	group_min_size = value


var group_max_size: int = 2:
	get:
		return group_max_size

func set_group_max_size(value: int) -> void:
	if multiplayer.is_server():
		group_max_size = value
		client_sync_group_max_size.rpc(group_max_size)
		SweetLogger.info("Set to {0}", [group_max_size])
	else:
		SweetLogger.info("Client (peer {0}) attempted direct set, forwarding to server", [multiplayer.get_unique_id()])
		server_set_group_max_size.rpc_id(1, value)

@rpc("any_peer", "call_remote", "reliable")
func server_set_group_max_size(value: int) -> void:
	set_group_max_size(value)

@rpc("authority", "call_remote", "reliable")
func client_sync_group_max_size(value: int) -> void:
	group_max_size = value


enum GameState {
	RUNNING,
	GAME_OVER,
	BUILDING
}

var game_state: GameState = GameState.BUILDING:
	get:
		return game_state

func set_game_state(value: GameState) -> void:
	if multiplayer.is_server():
		game_state = value
		client_sync_game_state.rpc(game_state)
		Signals.game_state_changed.emit(game_state)
		SweetLogger.info("Set to {0}", [game_state])
	else:
		SweetLogger.info("Client (peer {0}) attempted direct set, forwarding to server", [multiplayer.get_unique_id()])
		server_set_game_state.rpc_id(1, value)

@rpc("any_peer", "call_remote", "reliable")
func server_set_game_state(value: GameState) -> void:
	set_game_state(value)

@rpc("authority", "call_remote", "reliable")
func client_sync_game_state(value: GameState) -> void:
	game_state = value
	Signals.game_state_changed.emit(game_state)


func get_random_meal() -> String:
	if meals_in_play.size() == 0:
		SweetLogger.error("Get_random_meal() called but meals_in_play is empty")
		return ""
	var rand_index = randi() % meals_in_play.size()
	SweetLogger.debug("Get_random_meal() returning {0}", [meals_in_play[rand_index]])
	return meals_in_play[rand_index]


func get_random_side() -> String:
	SweetLogger.debug("->[]")
	if sides_in_play.size() == 0:
		SweetLogger.error("Get_random_side() called but sides_in_play is empty")
		return ""
	var rand_index = randi() % sides_in_play.size()
	SweetLogger.debug("List={0} returning {1}", [sides_in_play, sides_in_play[rand_index]], "GameManager.gd", "get_random_side")
	return sides_in_play[rand_index]


func _restart():
	SweetLogger.info("Restart game")
	game_state = GameState.RUNNING


func game_over():
	SweetLogger.info("Game over")
	game_state = GameState.GAME_OVER
	Signals.game_over.emit()
