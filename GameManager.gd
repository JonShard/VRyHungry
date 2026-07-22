class_name GameManager
extends Node

static var money: int
static var meals_in_play: Array[String]
static var sides_in_play: Array[String]


static func get_random_meal() -> String:
	if meals_in_play.size() == 0:
		push_error("GameManager: get_random_meal() called but meals_in_play is empty")
		return ""
	var rand_index = randi() % meals_in_play.size()
	print("GameManager: get_random_meal() returning ", meals_in_play[rand_index])
	return meals_in_play[rand_index]


static func get_random_side() -> String:
	if sides_in_play.size() == 0:
		push_error("GameManager: get_random_side() called but sides_in_play is empty")
		return ""
	var rand_index = randi() % sides_in_play.size()
	print("GameManager: get_random_side() returning ", sides_in_play[rand_index])
	return sides_in_play[rand_index]
