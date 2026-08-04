class_name GameManager
extends Node

static var money: int = 35
static var meals_in_play: Array[String]
static var sides_in_play: Array[String]

enum GameState {
	RUNNING,
	GAME_OVER,
	BUILDING
}
static var game_state: GameState = GameState.RUNNING: set = _set_game_state


static func _set_game_state(value: GameState):
	game_state = value
	Signals.game_state_changed.emit(value)


static func _restart():
	print("restart Game")
	game_state = GameState.RUNNING


static func get_random_meal() -> String:
	if meals_in_play.size() == 0:
		push_error("GameManager: get_random_meal() called but meals_in_play is empty")
		return ""
	var rand_index = randi() % meals_in_play.size()
	print("GameManager: get_random_meal() returning ", meals_in_play[rand_index])
	return meals_in_play[rand_index]


static func get_random_side() -> String:
	print("GameManager: get_random_side() ")
	if sides_in_play.size() == 0:
		push_error("GameManager: get_random_side() called but sides_in_play is empty")
		return ""
	var rand_index = randi() % sides_in_play.size()
	print("GameManager: get_random_side() list=%s returning %s" % [sides_in_play, sides_in_play[rand_index]])
	return sides_in_play[rand_index]


static  func game_over():
	print("Game Over")
	game_state = GameState.GAME_OVER
	Signals.game_over.emit()
