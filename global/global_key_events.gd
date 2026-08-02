extends Node

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit_game"):
		get_tree().quit()
	if event.is_action_pressed("satisfy_table_orders"):
		satisfy_table_orders()
	if event.is_action_pressed("set_building_mode"):
		set_buidling_mode()
	if event.is_action_pressed("set_running_mode"):
		set_running_mode()


# Finds any node of class/type Table and calls satisfyAllOrders()
func satisfy_table_orders() -> void:
	# Searches all nodes in the current running scene matching the class "Table"
	var table_nodes = get_tree().root.find_children("*", "Table", true, false)
	
	for node in table_nodes:
		if node.has_method("satisfyAllOrders"):
			node.satisfyAllOrders()
			
			
func set_buidling_mode():
	print("Global key event: Setting building mode")
	GameManager.game_state = GameManager.GameState.BUILDING


func set_running_mode():
	print("Global key event: Setting running mode")
	GameManager.game_state = GameManager.GameState.RUNNING
