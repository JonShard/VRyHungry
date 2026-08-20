extends Node

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit_game"):
		all_quit_game.rpc()
	if event.is_action_pressed("satisfy_table_orders"):
		satisfy_table_orders()
	if event.is_action_pressed("set_building_mode"):
		set_buidling_mode()
	if event.is_action_pressed("set_running_mode"):
		set_running_mode()
	if event.is_action_pressed("set_game_over"):
		set_game_over()

# Kill all clients
@rpc("any_peer", "call_local", "reliable")
func all_quit_game():
	SweetLogger.info("Quit game requested, killing all clients")
	get_tree().quit()

# Finds any node of class/type Table and calls satisfyAllOrders()
func satisfy_table_orders() -> void:
	SweetLogger.info("Debug: satisfying all table orders")
	# Searches all nodes in the current running scene matching the class "Table"
	var table_nodes = get_tree().root.find_children("*", "Table", true, false)

	for node in table_nodes:
		if node.has_method("satisfyAllOrders"):
			node.satisfyAllOrders()
			
			
func set_buidling_mode():
	SweetLogger.info("Setting building mode")
	GameManager.set_game_state(GameManager.GameState.BUILDING)


func set_running_mode():
	SweetLogger.info("Setting running mode")
	GameManager.set_game_state(GameManager.GameState.RUNNING)

func set_game_over():
	SweetLogger.info("Setting game over")
	GameManager.set_game_state(GameManager.GameState.GAME_OVER)
